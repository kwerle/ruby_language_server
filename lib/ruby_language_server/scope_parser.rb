# frozen_string_literal: true

require 'prism'
require_relative 'scope_parser_commands/rake_commands'
require_relative 'scope_parser_commands/rspec_commands'
require_relative 'scope_parser_commands/ruby_commands'
require_relative 'scope_parser_commands/rails_commands'

module RubyLanguageServer
  # A scope the parser has found but not stored yet: ScopeParser stores a file's scopes
  # together, with insert_all, once the whole file is parsed (PrismProcessor#store!).
  class PendingScope
    # id is given just before storing. parent is another PendingScope, or the file's
    # stored root Scope.
    attr_accessor :id, :superclass_name, :parameters, :class_method, :documentation
    attr_reader :parent, :class_type, :name, :path, :top_line, :bottom_line, :column

    def initialize(parent:, class_type:, name:, top_line:, bottom_line:, column:) # rubocop:disable Metrics/ParameterLists
      @parent = parent
      @class_type = class_type
      @name = name
      @path = [parent&.full_name, name].compact.join(ScopeData::Base::JoinHash[class_type])
      @top_line = top_line
      @bottom_line = bottom_line
      @column = column
      @class_method = false
    end

    def full_name
      path
    end

    def root_scope?
      false
    end

    def block_scope?
      class_type == ScopeData::Base::TYPE_BLOCK
    end

    def assign_parameters(params_array)
      self.parameters = params_array.to_json if params_array.present?
    end

    # The superclass as written, qualified with the enclosing namespace unless it starts
    # with :: (see Scope#superclass_scopes).
    def assign_superclass_name(partial)
      self.superclass_name = partial.start_with?('::') ? partial.delete_prefix('::') : [parent&.full_name, partial].compact.join(ScopeData::Base::JoinHash[class_type])
    end

    # The scopes table row. Every row has the same keys, as insert_all needs.
    def row(code_file_id)
      {
        id:, parent_id: parent.id, code_file_id:, class_type:, name:, path:, top_line:, bottom_line:, column:,
        superclass_name:, parameters:, class_method:, documentation:
      }
    end
  end

  # This class is responsible for processing the AST from Prism.
  # It builds scopes that amount to heirarchical arrays with information about what
  # classes, methods, variables, etc - are in each scope.
  class PrismProcessor < Prism::Visitor
    include ScopeParserCommands::RakeCommands
    include ScopeParserCommands::RspecCommands
    include ScopeParserCommands::RailsCommands
    include ScopeParserCommands::RubyCommands

    # Longest default value shown in a signature.
    DEFAULT_TEXT_LIMIT = 30
    # Comments above a definition that aren't documentation.
    MAGIC_COMMENT = /\A#\s*(frozen_string_literal|encoding|coding|warn_indent|shareable_constant_value|typed|rubocop:)/i

    INSERT_BATCH_SIZE = 1000

    attr_reader :current_scope, :lines

    # library: the file is from a gem (GemIndex). Only its classes, modules, methods and
    # constants are kept: its local variables and blocks never matter outside it.
    def initialize(lines = 1, code_file_id: nil, library: false)
      @lines = lines
      @code_file_id = code_file_id
      @library = library
      @root_scope = nil
      @current_scope = nil
      @block_names = {}
      @pending_scopes = []
      @pending_variables = []
      @variable_names = {}.compare_by_identity
    end

    def root_scope
      @root_scope ||= begin
        scope = ScopeData::Scope.where(path: nil, class_type: ScopeData::Scope::TYPE_ROOT, code_file_id: @code_file_id).first_or_create!
        @current_scope = scope
        scope
      end
    end

    # Stores the scopes and variables found, a batch of rows per statement. Block scopes
    # with no variables and nothing stored inside them are left out.
    #
    # Ids are given here, not by the database, so children can point at their parents
    # without reading ids back. That is safe because the caller's transaction already
    # holds SQLite's write lock (CodeFile deletes the file's old rows first), so no other
    # connection can insert between reading the largest id and inserting.
    def store!
      scopes = kept_scopes
      next_id = ScopeData::Scope.maximum(:id).to_i
      scopes.each { |scope| scope.id = (next_id += 1) }
      scopes.map { |scope| scope.row(@code_file_id) }.each_slice(INSERT_BATCH_SIZE) { |rows| ScopeData::Scope.insert_all!(rows) }

      kept = scopes.to_set.compare_by_identity
      variables = @pending_variables.select { |variable| variable[:scope].is_a?(ScopeData::Scope) || kept.include?(variable[:scope]) }
      variable_rows = variables.map do |variable|
        {name: variable[:name], line: variable[:line], column: variable[:column], scope_id: variable[:scope].id, code_file_id: @code_file_id}
      end
      variable_rows.each_slice(INSERT_BATCH_SIZE) { |rows| ScopeData::Variable.insert_all!(rows) }
    end

    # Visit a class node
    def visit_class_node(node)
      name = constant_path_name(node.constant_path)
      line = node.location.start_line
      end_line = node.location.end_line
      column = column_of(node.location)

      scope = push_scope(ScopeData::Scope::TYPE_CLASS, name, line, column, end_line)
      set_documentation(scope, node)

      # Handle superclass
      if node.superclass
        superclass_name = constant_path_name(node.superclass)
        scope.assign_superclass_name(superclass_name) if superclass_name
      end

      in_singleton_class(false) { super }
      pop_scope
    end

    # Visit a module node
    def visit_module_node(node)
      name = constant_path_name(node.constant_path)
      line = node.location.start_line
      end_line = node.location.end_line
      column = column_of(node.location)

      scope = push_scope(ScopeData::Scope::TYPE_MODULE, name, line, column, end_line)
      set_documentation(scope, node)
      in_singleton_class(false) { super }
      pop_scope
    end

    # Visit a def node
    def visit_def_node(node)
      name = node.name.to_s
      line = node.location.start_line
      end_line = node.location.end_line
      column = column_of(node.location)
      is_class_method = node.receiver.is_a?(Prism::SelfNode)

      scope = push_scope(ScopeData::Scope::TYPE_METHOD, name, line, column, end_line)
      # def self.name, or a plain def inside class << self
      scope.class_method = is_class_method || (node.receiver.nil? && @in_singleton_class)
      scope.documentation = documentation_for(node)
      scope.assign_parameters(extract_parameters_data(node.parameters)) if node.parameters

      # Process parameters (adds them as variables in scope)
      visit_parameters(node.parameters) if node.parameters

      super

      pop_scope
      scope
    end

    # Visit a singleton class (class << self)
    def visit_singleton_class_node(node)
      # For class << self, we visit the body but don't create a new scope.
      # The methods defined inside are class methods of the current scope.
      # class << some_object is not about the current class, so it doesn't count.
      in_singleton_class(node.expression.is_a?(Prism::SelfNode)) { super }
    end

    # Visit block nodes. A gem's blocks get no scope: methods defined in them (included do
    # ... end) belong to the enclosing class or module.
    def visit_block_node(node)
      name = @block_names.delete(node.object_id)
      return super if @library

      line = node.location.start_line
      end_line = node.location.end_line
      column = column_of(node.location)

      # Use block-specific name if set by command handler, otherwise use 'block'
      push_scope(ScopeData::Scope::TYPE_BLOCK, name || 'block', line, column, end_line)

      # Process block parameters
      visit_block_parameters(node.parameters) if node.parameters

      super
      pop_scope
    end

    # Visit local variable write nodes
    def visit_local_variable_write_node(node)
      name = node.name.to_s
      line = node.location.start_line
      column = column_of(node.location)

      add_variable(name, line, column)
      super
    end

    # Visit instance variable write nodes
    def visit_instance_variable_write_node(node)
      name = node.name.to_s
      line = node.location.start_line
      column = column_of(node.location)

      add_ivar(name, line, column)
      super
    end

    # Visit constant write nodes
    # FOO = 42
    def visit_constant_write_node(node)
      name = node.name.to_s
      line = node.location.start_line
      column = column_of(node.location)

      add_variable(name, line, column)
      super
    end

    # Visit multi-write nodes (parallel assignment)
    def visit_multi_write_node(node)
      node.lefts.each do |target|
        case target
        when Prism::LocalVariableTargetNode
          add_variable(target.name.to_s, target.location.start_line, column_of(target.location))
        when Prism::InstanceVariableTargetNode
          add_ivar(target.name.to_s, target.location.start_line, column_of(target.location))
        when Prism::MultiTargetNode
          # Handle nested destructuring like (a, (b, c)) = ...
          visit_multi_target(target)
        end
      end

      # Handle rest parameter in multi-assignment
      if node.rest.is_a?(Prism::SplatNode) && node.rest.expression
        case node.rest.expression
        when Prism::LocalVariableTargetNode
          add_variable(node.rest.expression.name.to_s, node.rest.expression.location.start_line, column_of(node.rest.expression.location))
        end
      end

      super
    end

    # Helper to handle nested multi-target nodes (for assignments)
    def visit_multi_target(node)
      node.lefts.each do |target|
        case target
        when Prism::LocalVariableTargetNode
          add_variable(target.name.to_s, target.location.start_line, column_of(target.location))
        when Prism::InstanceVariableTargetNode
          add_ivar(target.name.to_s, target.location.start_line, column_of(target.location))
        when Prism::MultiTargetNode
          visit_multi_target(target)
        end
      end
    end

    # Helper to extract variables from multi-target nodes (for parameters)
    # block_method { |(a, b), c| ... } # we need to extract a and b in addition to c
    def extract_multi_target_variables(node)
      node.lefts.each do |target|
        case target
        when Prism::RequiredParameterNode
          add_variable(target.name.to_s, target.location.start_line, column_of(target.location))
        when Prism::MultiTargetNode
          # Recursively handle nested destructuring
          extract_multi_target_variables(target)
        end
      end

      # Handle rest in multi-target (though rare in practice)
      if node.rest
        case node.rest
        when Prism::SplatNode
          add_variable(node.rest.expression.name.to_s, node.rest.expression.location.start_line, column_of(node.rest.expression.location)) if node.rest.expression.is_a?(Prism::RequiredParameterNode)
        end
      end

      # Handle rights (elements after rest)
      node.rights.each do |target|
        case target
        when Prism::RequiredParameterNode
          add_variable(target.name.to_s, target.location.start_line, column_of(target.location))
        when Prism::MultiTargetNode
          extract_multi_target_variables(target)
        end
      end
    end

    # Visit call nodes (method calls)
    def visit_call_node(node)
      name = node.name.to_s

      # Handle special commands like attr_accessor, private, etc.
      # Only handle if there's no receiver (i.e., it's a method call in current scope)
      if node.receiver.nil?
        block_node = node.block if node.block.is_a?(Prism::BlockNode)
        handle_command(name, node, block_node)

        # If the command pushed a scope for a block, pop it after visiting children
        should_pop = @command_pushed_scope
        @command_pushed_scope = false

        super

        pop_scope if should_pop
      else
        super
      end
    end

    private

    # LSP character offsets count UTF-16 code units. Prism's start_column counts bytes,
    # which differ from code units on any line with non-ASCII text before the node.
    def column_of(location)
      location.start_code_units_column(Encoding::UTF_16LE)
    end

    def set_documentation(scope, node)
      scope.documentation = documentation_for(node)
    end

    # A method's parameters in source order, as { name:, type: } hashes, with default:
    # (source text) for optional ones. Rest, keyword rest and block names carry their
    # sigil, and keyword names their trailing colon. Anonymous ones are just the sigil.
    def extract_parameters_data(params_node)
      return [] unless params_node

      params = params_node.requireds.map { |param| required_parameter_data(param) }
      params += params_node.optionals.map { |param| {name: param.name.to_s, type: 'optional', default: default_text(param.value)} }
      params << rest_parameter_data(params_node.rest) if params_node.rest
      params += params_node.posts.map { |param| required_parameter_data(param) }
      params += params_node.keywords.map { |param| keyword_parameter_data(param) }
      params << keyword_rest_parameter_data(params_node.keyword_rest) if params_node.keyword_rest
      params << {name: "&#{params_node.block.name}", type: 'block'} if params_node.block
      params
    end

    def required_parameter_data(param)
      # Destructuring, like def f((a, b)), is shown as written.
      name = param.is_a?(Prism::RequiredParameterNode) ? param.name.to_s : param.slice
      {name:, type: 'required'}
    end

    def rest_parameter_data(rest)
      # An ImplicitRestNode is the trailing comma in a block's |a, |. Not a real parameter.
      return {name: "*#{rest.name}", type: 'rest'} if rest.is_a?(Prism::RestParameterNode)

      {name: rest.slice, type: 'rest'}
    end

    def keyword_parameter_data(param)
      name = "#{param.name}:"
      return {name:, type: 'keyword'} if param.is_a?(Prism::RequiredKeywordParameterNode)

      {name:, type: 'optional_keyword', default: default_text(param.value)}
    end

    def keyword_rest_parameter_data(keyword_rest)
      case keyword_rest
      when Prism::ForwardingParameterNode then {name: '...', type: 'forwarding'}
      when Prism::NoKeywordsParameterNode then {name: '**nil', type: 'no_keyword'}
      else {name: "**#{keyword_rest.name}", type: 'keyword_rest'}
      end
    end

    # The source of a default value, on one line and cut short if it is long.
    def default_text(node)
      text = node.slice.gsub(/\s*\n\s*/, ' ')
      text.length > DEFAULT_TEXT_LIMIT ? "#{text[0, DEFAULT_TEXT_LIMIT - 1]}…" : text
    end

    # The # comment lines directly above node, without their leading "# ", or nil.
    # Needs ParseResult#attach_comments!. A blank line ends the block, and magic
    # comments and rubocop directives are left out.
    def documentation_for(node)
      comments = node.location.leading_comments.grep(Prism::InlineComment)
      block = []
      expected_line = node.location.start_line - 1
      comments.reverse_each do |comment|
        break unless comment.location.start_line == expected_line

        block.unshift(comment)
        expected_line -= 1
      end
      text = block.map(&:slice).grep_v(MAGIC_COMMENT).map { |line| line.sub(/\A#\s?/, '') }
      text.join("\n").strip.presence
    end

    def visit_parameters(params_node)
      return unless params_node

      # Required parameters
      params_node.requireds.each do |param|
        case param
        when Prism::RequiredParameterNode
          add_variable(param.name.to_s, param.location.start_line, column_of(param.location))
        when Prism::MultiTargetNode
          # Handle destructuring in parameters like |(a, b), c|
          extract_multi_target_variables(param)
        end
      end

      # Optional parameters
      params_node.optionals.each do |param|
        add_variable(param.name.to_s, param.location.start_line, column_of(param.location))
      end

      # Rest parameter
      add_variable(params_node.rest.name.to_s, params_node.rest.location.start_line, column_of(params_node.rest.location)) if params_node.rest.is_a?(Prism::RestParameterNode) && params_node.rest.name

      # Parameters after the rest parameter, like b in def f(*a, b)
      params_node.posts.each do |param|
        case param
        when Prism::RequiredParameterNode
          add_variable(param.name.to_s, param.location.start_line, column_of(param.location))
        when Prism::MultiTargetNode
          extract_multi_target_variables(param)
        end
      end

      # Keyword parameters
      params_node.keywords.each do |param|
        name = param.name.to_s
        add_variable(name, param.location.start_line, column_of(param.location))
      end

      # Keyword rest parameter
      add_variable(params_node.keyword_rest.name.to_s, params_node.keyword_rest.location.start_line, column_of(params_node.keyword_rest.location)) if params_node.keyword_rest.is_a?(Prism::KeywordRestParameterNode) && params_node.keyword_rest.name

      # Block parameter
      add_variable(params_node.block.name.to_s, params_node.block.location.start_line, column_of(params_node.block.location)) if params_node.block&.name
    end

    # Numbered (_1) and it parameters have no parameter list, and nothing to record.
    def visit_block_parameters(params_node)
      return unless params_node.is_a?(Prism::BlockParametersNode)

      visit_parameters(params_node.parameters) if params_node.parameters
    end

    def constant_path_name(node)
      case node
      when Prism::ConstantReadNode
        node.name.to_s
      when Prism::ConstantPathNode
        # For Some::Class, we need to recursively build the path
        parts = []

        # Add the rightmost name (e.g., "Class" in Some::Class)
        parts << node.name.to_s

        # Traverse the parent chain
        current = node.parent
        while current
          case current
          when Prism::ConstantReadNode
            parts.unshift(current.name.to_s)
            current = nil
          when Prism::ConstantPathNode
            parts.unshift(current.name.to_s)
            current = current.parent
          else
            current = nil
          end
        end

        parts.join('::')
      else
        node.to_s if node.respond_to?(:to_s)
      end
    end

    # Calls on_<name>_command(node) from ScopeParserCommands, if there is one, with
    # @current_block_node set to the call's block. Handlers read the call with
    # command_line, command_column and command_arguments.
    def handle_command(name, node, block_node = nil)
      method_name = "on_#{name}_command"
      # Most calls (puts, require, each, ...) have no handler. Don't log those: there's one
      # per call in every file.
      return unless respond_to?(method_name)

      @current_block_node = block_node
      send(method_name, node)
      @current_block_node = nil
    end

    def command_line(node)
      node.location.start_line
    end

    def command_column(node)
      column_of(node.location)
    end

    # The last line of the command's block, or its own line if it has none.
    def command_end_line(node)
      @current_block_node ? @current_block_node.location.end_line : command_line(node)
    end

    # The command's arguments that name things, as strings, in order:
    # symbols (attr_reader :foo), strings (describe 'thing'), constants
    # (describe Some::Class) and symbol keys of a keyword hash with a trailing colon
    # (task something: [] becomes "something:").
    def command_arguments(node)
      return [] unless node.arguments

      args = []
      node.arguments.arguments.each do |arg|
        case arg
        when Prism::SymbolNode
          # Extract symbol name
          args << arg.value.to_s if arg.value
        when Prism::StringNode
          args << arg.unescaped
        when Prism::ConstantReadNode
          # Handle constant arguments like: describe SomeClass
          args << arg.name.to_s
        when Prism::ConstantPathNode
          # Handle constant path arguments like: describe Some::Class
          args << constant_path_name(arg)
        when Prism::KeywordHashNode
          # Handle keyword arguments like: task something: [] do
          # Extract the keys which are the task names
          arg.elements.each do |element|
            if element.is_a?(Prism::AssocNode) && element.key.is_a?(Prism::SymbolNode)
              # Add the colon suffix to match Rake syntax expectations
              args << "#{element.key.value}:"
            end
          end
        end
      end
      args
    end

    # Records the first assignment of each name in a scope; later ones are skipped. A gem's
    # files only keep constants.
    def add_variable(name, line, column, scope = @current_scope)
      return if scope.nil?
      return if @library && !name.match?(/\A[A-Z]/)
      return unless variable_names_in(scope).add?(name)

      @pending_variables << {scope:, name:, line:, column:}
    end

    # Names of the variables recorded in scope. Scopes this parse created start empty.
    # Only the root can already have rows (ScopeParser reuses an existing root), so its
    # names are read from the database once.
    def variable_names_in(scope)
      @variable_names[scope] ||= scope.root_scope? ? Set.new(scope.variables.pluck(:name)) : Set.new
    end

    def add_ivar(name, line, column)
      scope = @current_scope
      return if scope.nil?

      unless scope == root_scope
        ivar_scope_types = [ScopeData::Base::TYPE_CLASS, ScopeData::Base::TYPE_MODULE]
        while !ivar_scope_types.include?(scope.class_type) && !scope.parent.nil?
          scope = scope.parent
        end
      end
      add_variable(name, line, column, scope)
    end

    # Runs the block with @in_singleton_class set, restoring it afterwards. A class or
    # module nested inside class << self starts fresh.
    def in_singleton_class(value)
      saved = @in_singleton_class
      @in_singleton_class = value
      yield
    ensure
      @in_singleton_class = saved
    end

    def type_is_class_or_module(type)
      [RubyLanguageServer::ScopeData::Base::TYPE_CLASS, RubyLanguageServer::ScopeData::Base::TYPE_MODULE].include?(type)
    end

    def push_scope(type, name, top_line, column, end_line)
      new_scope = PendingScope.new(parent: @current_scope, class_type: type, name:, top_line:, bottom_line: end_line, column:)
      @pending_scopes << new_scope
      @current_scope = new_scope
    end

    # The pending scopes to store: all but blocks with no variables and nothing kept
    # inside them. Children come after their parents, so walking backwards sees each
    # scope's children first.
    def kept_scopes
      with_variables = @pending_variables.to_set { |variable| variable[:scope] }.compare_by_identity
      needed = Set.new.compare_by_identity
      kept = @pending_scopes.reverse.select do |scope|
        keep = !scope.block_scope? || with_variables.include?(scope) || needed.include?(scope)
        needed << scope.parent if keep
        keep
      end
      kept.reverse
    end

    def pop_scope
      @current_scope = @current_scope.parent || root_scope # in case we are leaving a root class/module
    end
  end

  # This class builds on Prism's AST processor to add ruby and rails magic.
  # Specifically it knows about things like alias, attr_*, has_one/many, etc.
  # It adds the appropriate definitions for those magic words.
  class ScopeParser
    attr_reader :root_scope

    # code_file_id is the CodeFile the scopes belong to (nil in some specs). library is true
    # for a gem's file (see PrismProcessor#initialize).
    def initialize(text, code_file_id: nil, library: false)
      text ||= '' # empty is the same as nil - but it doesn't crash
      line_count = text.split("\n").length
      # A savepoint, so a failed parse leaves nothing behind in the caller's transaction.
      ScopeData::Scope.transaction(requires_new: true) do
        result = Prism.parse(text)
        result.attach_comments!
        processor = PrismProcessor.new(line_count, code_file_id:, library:)
        processor.root_scope # Initialize root scope
        result.value.accept(processor)
        processor.store!
        @root_scope = processor.root_scope
      end
    rescue StandardError => e
      RubyLanguageServer.logger.error("Exception in prism parsing: #{e.class}: #{e} (#{line_count} lines)\n#{e.backtrace&.first(5)&.join("\n")}")
      # Nothing from the failed parse was stored. Leave an empty root.
      @root_scope = PrismProcessor.new(line_count, code_file_id:, library:).root_scope
    end
  end
end
