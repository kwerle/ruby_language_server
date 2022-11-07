# frozen_string_literal: true

require 'ripper'
require_relative 'scope_parser_commands/rake_commands'
require_relative 'scope_parser_commands/rspec_commands'
require_relative 'scope_parser_commands/ruby_commands'
require_relative 'scope_parser_commands/rails_commands'

module RubyLanguageServer
  # This class is responsible for processing the generated sexp from the ScopeParser below.
  # It builds scopes that amount to heirarchical arrays with information about what
  # classes, methods, variables, etc - are in each scope.
  class SEXPProcessor
    include ScopeParserCommands::RakeCommands
    include ScopeParserCommands::RspecCommands
    include ScopeParserCommands::RailsCommands
    include ScopeParserCommands::RubyCommands
    attr_reader :sexp, :lines, :current_scope

    def initialize(sexp, lines = 1)
      @sexp = sexp
      @lines = lines
      @root_scope = nil
    end

    def root_scope
      return @root_scope unless @root_scope.nil?

      @root_scope = ScopeData::Scope.where(path: nil, class_type: ScopeData::Scope::TYPE_ROOT).first_or_create!
      @current_scope = @root_scope
      process(@sexp)
      @root_scope
    end

    def process(sexp)
      return if sexp.nil?

      root, args, *rest = sexp
      # RubyLanguageServer.logger.error("Doing #{[root, args, rest]}")
      case root
      when Array
        sexp.each { |child| process(child) }
      when Symbol
        root = root.to_s.gsub(/^@+/, '')
        method_name = "on_#{root}"
        if respond_to? method_name
          send(method_name, args, rest)
        else
          RubyLanguageServer.logger.debug("We don't have a #{method_name} with #{args}")
          process(args)
        end
      when String
        # We really don't do anything with it!
        RubyLanguageServer.logger.debug("We don't do Strings like #{root} with #{args}")
      when NilClass, FalseClass
        process(args)
      else
        RubyLanguageServer.logger.warn("We don't respond to the likes of #{root} of class #{root.class}")
      end
    end

    def on_sclass(_args, rest)
      process(rest)
    end

    # foo = bar -- bar is in the vcall.  Pretty sure we don't want to remember this.
    def on_vcall(_args, rest)
      # Seriously - discard args.  Maybe process rest?
      process(rest)
    end

    def on_program(args, _rest)
      process(args)
    end

    def on_var_field(args, rest)
      (_, name, (line, column)) = args
      return if name.nil?

      if name.start_with?('@')
        add_ivar(name, line, column)
      else
        add_variable(name, line, column)
      end
      process(rest)
    end

    def on_bodystmt(args, _rest)
      process(args)
    end

    def on_module(args, rest)
      scope = add_scope(args.last, rest, ScopeData::Scope::TYPE_MODULE)
      assign_subclass(scope, rest)
    end

    def on_class(args, rest)
      scope = add_scope(args.last, rest, ScopeData::Scope::TYPE_CLASS)
      assign_subclass(scope, rest)
    end

    def assign_subclass(scope, sexp)
      return unless !sexp[0].nil? && sexp[0][0] == :var_ref

      (_, (_, name)) = sexp[0]
      scope.set_superclass_name(name)
    end

    def on_method_add_block(args, rest)
      scope = @current_scope
      process(args)
      process(rest)
      # add_scope(args, rest, ScopeData::Scope::TYPE_BLOCK)
      unless @current_scope == scope
        scope.bottom_line = [scope&.bottom_line, @current_scope.bottom_line].compact.max
        scope.save!
        pop_scope
      end
    end

    def on_do_block(args, rest)
      ((_, ((_, (_, (_, _name, (line, column))))))) = args
      push_scope(ScopeData::Scope::TYPE_BLOCK, 'block', line, column, false)
      process(args)
      process(rest)
      pop_scope
    end

    def on_block_var(args, rest)
      process(args)
      process(rest)
    end

    # Used only to describe subclasses? -- nope
    def on_var_ref(_args, _rest)
      # [:@const, "Bar", [13, 20]]
      # (_, name) = args
      # @current_scope.set_superclass_name(name)
    end

    def on_assign(args, rest)
      process(args)
      process(rest)
    end

    def on_def(args, rest)
      add_scope(args, rest, ScopeData::Scope::TYPE_METHOD)
    end

    # def self.something(par)...
    # [:var_ref, [:@kw, "self", [28, 14]]], [[:@period, ".", [28, 18]], [:@ident, "something", [28, 19]], [:paren, [:params, [[:@ident, "par", [28, 23]]], nil, nil, nil, nil, nil, nil]], [:bodystmt, [[:assign, [:var_field, [:@ident, "pax", [29, 12]]], [:var_ref, [:@ident, "par", [29, 18]]]]], nil, nil, nil]]
    def on_defs(args, rest)
      on_def(rest[1], rest[2..]) if args[1][1] == 'self' && rest[0][1] == '.'
    end

    # Multiple left hand side
    # (foo, bar) = somethingg...
    def on_mlhs(args, rest)
      process(args)
      process(rest)
    end

    # ident is something that gets processed at parameters to a function or block
    def on_ident(name, ((line, column)))
      add_variable(name, line, column)
    end

    def on_params(args, rest)
      process(args)
      process(rest)
    end

    # The on_command function idea is stolen from RipperTags https://github.com/tmm1/ripper-tags/blob/master/lib/ripper-tags/parser.rb
    def on_command(args, rest)
      # [:@ident, "public", [6, 8]]
      (_, name, (line, _column)) = args

      method_name = "on_#{name}_command"
      if respond_to? method_name
        return send(method_name, line, args, rest)
      else
        RubyLanguageServer.logger.debug("We don't have a #{method_name} with #{args}")
      end

      case name
      when 'public', 'private', 'protected'
        # FIXME: access control...
        process(rest)
      when 'delegate'
        # on_delegate(*args[0][1..-1])
      when 'def_delegator', 'def_instance_delegator'
        # on_def_delegator(*args[0][1..-1])
      when 'def_delegators', 'def_instance_delegators'
        # on_def_delegators(*args[0][1..-1])
      end
    end

    # The on_method_add_arg function is downright stolen from RipperTags https://github.com/tmm1/ripper-tags/blob/master/lib/ripper-tags/parser.rb
    def on_method_add_arg(call, args)
      call_name = call && call[0]
      first_arg = args && args[0] == :args && args[1]

      if call_name == :call && first_arg
        if args.length == 2
          # augment call if a single argument was used
          call = call.dup
          call[3] = args[1]
        end
        call
      elsif call_name == :fcall && first_arg
        name, line = call[1]
        case name
        when 'alias_method' # this is an fcall
          [:alias, args[1][0], args[2][0], line] if args[1] && args[2]
        when 'define_method' # this is an fcall
          [:def, args[1][0], line]
        when 'public_class_method', 'private_class_method', 'private', 'public', 'protected'
          access = name.sub('_class_method', '')

          if args[1][1] == 'self'
            klass = 'self'
            method_name = args[1][2]
          else
            klass = nil
            method_name = args[1][1]
          end

          [:def_with_access, klass, method_name, access, line]
        end
      end
    end

    private

    def add_variable(name, line, column, scope = @current_scope)
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
      unless scope == root_scope
        ivar_scope_types = [ScopeData::Base::TYPE_CLASS, ScopeData::Base::TYPE_MODULE]
        while !ivar_scope_types.include?(scope.class_type) && !scope.parent.nil?
          scope = scope.parent
        end
      end
      add_variable(name, line, column, scope)
    end

    def add_scope(args, rest, type)
      (_, name, (line, column)) = args
      scope = push_scope(type, name, line, column)
      process(rest)
      pop_scope
      scope
    end

    def type_is_class_or_module(type)
      [RubyLanguageServer::ScopeData::Base::TYPE_CLASS, RubyLanguageServer::ScopeData::Base::TYPE_MODULE].include?(type)
    end

    def push_scope(type, name, top_line, column, close_siblings = true)
      close_sibling_scopes(top_line) if close_siblings
      new_scope = ScopeData::Scope.build(@current_scope, type, name, top_line, column)
      new_scope.bottom_line = @lines
      new_scope.save!
      @current_scope = new_scope
    end

    # This is a very poor man's "end" handler because there is no end handler.
    # The notion is that when you start the next scope, all the previous peers and unclosed descendents of the previous peer should be closed.
    def close_sibling_scopes(line)
      parent_scope = @current_scope
      parent_scope&.descendants&.each { |scope| scope.close(line) }
    end

    def pop_scope
      @current_scope = @current_scope.parent || root_scope # in case we are leaving a root class/module
    end
  end

  # This class builds on Ripper's sexp processor to add ruby and rails magic.
  # Specifically it knows about things like alias, attr_*, has_one/many, etc.
  # It adds the appropriate definitions for those magic words.
  class ScopeParser < Ripper
    attr_reader :root_scope

    def initialize(text)
      text ||= '' # empty is the same as nil - but it doesn't crash
      begin
        sexp = self.class.sexp(text)
      rescue TypeError => e
        RubyLanguageServer.logger.error("Exception in sexp: #{e} for text: #{text}")
      end
      processor = SEXPProcessor.new(sexp, text.split("\n").length)
      @root_scope = processor.root_scope
    end
  end
end
