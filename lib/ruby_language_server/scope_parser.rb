# frozen_string_literal: true

require 'prism'
require_relative 'scope_parser_commands/rake_commands'
require_relative 'scope_parser_commands/rspec_commands'
require_relative 'scope_parser_commands/ruby_commands'
require_relative 'scope_parser_commands/rails_commands'

module RubyLanguageServer
  # This class is responsible for processing the AST from Prism.
  # It builds scopes that amount to heirarchical arrays with information about what
  # classes, methods, variables, etc - are in each scope.
  class PrismProcessor < Prism::Visitor
    include ScopeParserCommands::RakeCommands
    include ScopeParserCommands::RspecCommands
    include ScopeParserCommands::RailsCommands
    include ScopeParserCommands::RubyCommands
    attr_reader :current_scope, :lines

    def initialize(lines = 1, shallow = false)
      @lines = lines
      @shallow = shallow
      @root_scope = nil
      @current_scope = nil
      @block_names = {}
    end

    def root_scope
      @root_scope ||= begin
        scope = ScopeData::Scope.where(path: nil, class_type: ScopeData::Scope::TYPE_ROOT).first_or_create!
        @current_scope = scope
        scope
      end
    end

    # Visit a class node
    def visit_class_node(node)
      name = constant_path_name(node.constant_path)
      line = node.location.start_line
      end_line = node.location.end_line
      column = node.location.start_column

      scope = push_scope(ScopeData::Scope::TYPE_CLASS, name, line, column, end_line)

      # Handle superclass
      if node.superclass
        superclass_name = constant_path_name(node.superclass)
        scope.set_superclass_name(superclass_name) if superclass_name
      end

      super
      pop_scope
    end

    # Visit a module node
    def visit_module_node(node)
      name = constant_path_name(node.constant_path)
      line = node.location.start_line
      end_line = node.location.end_line
      column = node.location.start_column

      push_scope(ScopeData::Scope::TYPE_MODULE, name, line, column, end_line)
      super
      pop_scope
    end

    # Visit a def node
    def visit_def_node(node)
      name = node.name.to_s
      line = node.location.start_line
      end_line = node.location.end_line
      column = node.location.start_column

      scope = push_scope(ScopeData::Scope::TYPE_METHOD, name, line, column, end_line, false)

      # Process parameters
      visit_parameters(node.parameters) if node.parameters

      # Process body only if not shallow
      if @shallow
        # Skip body processing
      else
        super
      end

      pop_scope
      scope
    end

    # Visit a singleton class (class << self)
    def visit_singleton_class_node(node) # rubocop:disable Lint/UselessMethodDefinition:
      # For class << self, we visit the body but don't create a new scope
      # The methods defined inside will be class methods of the current scope
      super
    end

    # Visit block nodes
    def visit_block_node(node)
      line = node.location.start_line
      end_line = node.location.end_line
      column = node.location.start_column

      # Use block-specific name if set by command handler, otherwise use 'block'
      name = @block_names.delete(node.object_id) || 'block'

      push_scope(ScopeData::Scope::TYPE_BLOCK, name, line, column, end_line, false)

      # Process block parameters
      visit_block_parameters(node.parameters) if node.parameters

      super
      pop_scope
    end

    # Visit local variable write nodes
    def visit_local_variable_write_node(node)
      name = node.name.to_s
      line = node.location.start_line
      column = node.location.start_column

      add_variable(name, line, column)
      super
    end

    # Visit instance variable write nodes
    def visit_instance_variable_write_node(node)
      name = node.name.to_s
      line = node.location.start_line
      column = node.location.start_column

      add_ivar(name, line, column)
      super
    end

    # Visit constant write nodes
    # FOO = 42
    def visit_constant_write_node(node)
      name = node.name.to_s
      line = node.location.start_line
      column = node.location.start_column

      add_variable(name, line, column)
      super
    end

    # Visit multi-write nodes (parallel assignment)
    def visit_multi_write_node(node)
      node.lefts.each do |target|
        case target
        when Prism::LocalVariableTargetNode
          add_variable(target.name.to_s, target.location.start_line, target.location.start_column)
        when Prism::InstanceVariableTargetNode
          add_ivar(target.name.to_s, target.location.start_line, target.location.start_column)
        when Prism::MultiTargetNode
          # Handle nested destructuring like (a, (b, c)) = ...
          visit_multi_target(target)
        end
      end

      # Handle rest parameter in multi-assignment
      if node.rest.is_a?(Prism::SplatNode) && node.rest.expression
        case node.rest.expression
        when Prism::LocalVariableTargetNode
          add_variable(node.rest.expression.name.to_s, node.rest.expression.location.start_line, node.rest.expression.location.start_column)
        end
      end

      super
    end

    # Helper to handle nested multi-target nodes (for assignments)
    def visit_multi_target(node)
      node.lefts.each do |target|
        case target
        when Prism::LocalVariableTargetNode
          add_variable(target.name.to_s, target.location.start_line, target.location.start_column)
        when Prism::InstanceVariableTargetNode
          add_ivar(target.name.to_s, target.location.start_line, target.location.start_column)
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
          add_variable(target.name.to_s, target.location.start_line, target.location.start_column)
        when Prism::MultiTargetNode
          # Recursively handle nested destructuring
          extract_multi_target_variables(target)
        end
      end

      # Handle rest in multi-target (though rare in practice)
      if node.rest
        case node.rest
        when Prism::SplatNode
          add_variable(node.rest.expression.name.to_s, node.rest.expression.location.start_line, node.rest.expression.location.start_column) if node.rest.expression.is_a?(Prism::RequiredParameterNode)
        end
      end

      # Handle rights (elements after rest)
      node.rights.each do |target|
        case target
        when Prism::RequiredParameterNode
          add_variable(target.name.to_s, target.location.start_line, target.location.start_column)
        when Prism::MultiTargetNode
          extract_multi_target_variables(target)
        end
      end
    end

    # Visit call nodes (method calls)
    def visit_call_node(node)
      name = node.name.to_s
      line = node.location.start_line

      # Handle special commands like attr_accessor, private, etc.
      # Only handle if there's no receiver (i.e., it's a method call in current scope)
      if node.receiver.nil?
        block_node = node.block if node.block.is_a?(Prism::BlockNode)
        handle_command(name, line, node, block_node)

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

    def visit_parameters(params_node)
      return unless params_node

      # Required parameters
      params_node.requireds.each do |param|
        case param
        when Prism::RequiredParameterNode
          add_variable(param.name.to_s, param.location.start_line, param.location.start_column)
        when Prism::MultiTargetNode
          # Handle destructuring in parameters like |(a, b), c|
          extract_multi_target_variables(param)
        end
      end

      # Optional parameters
      params_node.optionals.each do |param|
        add_variable(param.name.to_s, param.location.start_line, param.location.start_column)
      end

      # Rest parameter
      add_variable(params_node.rest.name.to_s, params_node.rest.location.start_line, params_node.rest.location.start_column) if params_node.rest&.name

      # Keyword parameters
      params_node.keywords.each do |param|
        name = param.name.to_s
        add_variable(name, param.location.start_line, param.location.start_column)
      end

      # Keyword rest parameter
      add_variable(params_node.keyword_rest.name.to_s, params_node.keyword_rest.location.start_line, params_node.keyword_rest.location.start_column) if params_node.keyword_rest && params_node.keyword_rest.name

      # Block parameter
      add_variable(params_node.block.name.to_s, params_node.block.location.start_line, params_node.block.location.start_column) if params_node.block && params_node.block.name
    end

    def visit_block_parameters(params_node)
      return unless params_node

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

    def handle_command(name, line, node, block_node = nil)
      method_name = "on_#{name}_command"
      if respond_to?(method_name)
        # Extract arguments from Prism node and format for command handler
        args = extract_command_args(node)
        rest = extract_command_rest(node)
        @current_block_node = block_node
        send(method_name, line, args, rest)
        @current_block_node = nil
      else
        RubyLanguageServer.logger.debug("We don't have a #{method_name}")
      end
    end

    # Extract arguments in format expected by command handlers
    # Returns: [:@ident, "method_name", [line, column]]
    def extract_command_args(node)
      [:@ident, node.name.to_s, [node.location.start_line, node.location.start_column]]
    end

    # Extract the rest/body arguments from a call node
    # For attr methods, this needs to extract symbol arguments
    # For rake tasks, this needs to extract keyword hash keys
    # For rspec commands, this needs to extract constant paths
    def extract_command_rest(node)
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

    def add_variable(name, line, column, scope = @current_scope)
      return if @shallow
      return if scope.nil?

      newvar = scope.variables.where(name:).first_or_create!(
        line:,
        column:,
        code_file: scope.code_file
      )
      if scope.top_line.blank?
        scope.top_line = line
        scope.save!
      end
      newvar
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

    def type_is_class_or_module(type)
      [RubyLanguageServer::ScopeData::Base::TYPE_CLASS, RubyLanguageServer::ScopeData::Base::TYPE_MODULE].include?(type)
    end

    def push_scope(type, name, top_line, column, end_line, close_siblings = true)
      close_sibling_scopes(top_line) if close_siblings
      new_scope = ScopeData::Scope.build(@current_scope, type, name, top_line, column)
      new_scope.bottom_line = end_line
      new_scope.save!
      @current_scope = new_scope
    end

    # Clean up any empty block scopes when starting a new sibling scope.
    def close_sibling_scopes(_line)
      parent_scope = @current_scope
      parent_scope&.descendants&.each(&:close)
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

    def initialize(text, shallow = false)
      text ||= '' # empty is the same as nil - but it doesn't crash
      begin
        result = Prism.parse(text)
        processor = PrismProcessor.new(text.split("\n").length, shallow)
        processor.root_scope # Initialize root scope
        result.value.accept(processor)
        @root_scope = processor.root_scope
      rescue StandardError => e
        RubyLanguageServer.logger.error("Exception in prism parsing: #{e} for text: #{text}")
        # Create an empty root scope on error
        processor = PrismProcessor.new(text.split("\n").length, shallow)
        @root_scope = processor.root_scope
      end
    end
  end
end
