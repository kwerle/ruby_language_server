require 'ripper'

module RubyLanguageServer

  # This class is responsible for processing the generated sexp from the ScopeParser below.
  # It builds scopes that amount to heirarchical arrays with information about what
  # classes, methods, variables, etc - are in each scope.
  class SEXPProcessor
    attr :sexp
    attr_reader :current_scope

    def initialize(sexp)
      @sexp = sexp
    end

    def root_scope
      return @root_scope unless @root_scope.nil?
      @root_scope = new_root_scope()
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
        sexp.each{ |child| process(child) }
      when Symbol
        method_name = "on_#{root.to_s}"
        if respond_to? method_name
          self.send(method_name, args, rest)
        else
          RubyLanguageServer.logger.error("We don't have a #{method_name} with #{args}")
          process(args)
        end
      when NilClass
        process(args)
      else
        RubyLanguageServer.logger.error("We don't respond to the likes of #{root} of class #{root.class}")
        # byebug
      end
    end

    def on_program(args, rest)
      process(args)
    end

    # def on_assign(args, rest)
    #   # [:var_field, [:@ident, "zang", [4, 10]]]
    #   # (_, (_, name, (line, column))) = args
    #   name = process(args)
    #   return if name.nil?
    #   if name.start_with?('@')
    #     add_ivar(name, line, column)
    #   else
    #     add_variable(name, line, column)
    #   end
    #   process(rest)
    # end

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

    def on_bodystmt(args, rest)
      process(args)
    end

    def on_module(args, rest)
      add_scope(args.last, rest, ScopeData::Scope::TYPE_MODULE)
    end

    def on_class(args, rest)
      add_scope(args.last, rest, ScopeData::Scope::TYPE_CLASS)
    end

    def on_def(args, rest)
      add_scope(args, rest, ScopeData::Scope::TYPE_METHOD)
    end

    def on_params(args, rest)
      return if args.nil?
      # [[:@ident, "bing", [3, 16]], [:@ident, "zing", [3, 22]]]
      args.each do |_, name, (line, column)|
        add_variable(name, line, column)
      end
    end

    # The on_command function idea is stolen from RipperTags https://github.com/tmm1/ripper-tags/blob/master/lib/ripper-tags/parser.rb
    def on_command(args, rest)
      # [:@ident, "public", [6, 8]]
      (_, name, (line, column)) = args
      case name
      when 'public', 'private', 'protected'
        # FIXME access control...
        process(rest)
      when "define_method", "alias_method",
           "has_one", "has_many",
           "belongs_to", "has_and_belongs_to_many",
           "scope", "named_scope",
           "public_class_method", "private_class_method",
           "public", "protected", "private",
           /^attr_(accessor|reader|writer)$/
        # on_method_add_arg([:fcall, name], args[0])
      when "attr"
        # [[:args_add_block, [[:symbol_literal, [:symbol, [:@ident, "top", [3, 14]]]]], false]]
        ((_, ((_, (_, (_, name, (line, column))))))) = rest
        add_ivar("@#{name}", line, column)
        push_scope(ScopeData::Scope::TYPE_METHOD, name, line, column)
        pop_scope()
        push_scope(ScopeData::Scope::TYPE_METHOD, "#{name}=", line, column)
        pop_scope()
      when "delegate"
        # on_delegate(*args[0][1..-1])
      when "def_delegator", "def_instance_delegator"
        # on_def_delegator(*args[0][1..-1])
      when "def_delegators", "def_instance_delegators"
        # on_def_delegators(*args[0][1..-1])
      end
    end

    # The on_method_add_arg function is downright stolen from RipperTags https://github.com/tmm1/ripper-tags/blob/master/lib/ripper-tags/parser.rb
    def on_method_add_arg(call, args)
      call_name = call && call[0]
      first_arg = args && :args == args[0] && args[1]

      if :call == call_name && first_arg
        if args.length == 2
          # augment call if a single argument was used
          call = call.dup
          call[3] = args[1]
        end
        call
      elsif :fcall == call_name && first_arg
        name, line = call[1]
        case name
        when "alias_method"
          [:alias, args[1][0], args[2][0], line] if args[1] && args[2]
        when "define_method"
          [:def, args[1][0], line]
        when "public_class_method", "private_class_method", "private", "public", "protected"
          access = name.sub("_class_method", "")

          if args[1][1] == 'self'
            klass = 'self'
            method_name = args[1][2]
          else
            klass = nil
            method_name = args[1][1]
          end

          [:def_with_access, klass, method_name, access, line]
        when "scope", "named_scope"
          [:rails_def, :scope, args[1][0], line]
        when /^attr_(accessor|reader|writer)$/
          gen_reader = $1 != 'writer'
          gen_writer = $1 != 'reader'
          args[1..-1].inject([]) do |gen, arg|
            gen << [:def, arg[0], line] if gen_reader
            gen << [:def, "#{arg[0]}=", line] if gen_writer
            gen
          end
        when "has_many", "has_and_belongs_to_many"
          a = args[1][0]
          kind = name.to_sym
          gen = []
          unless a.is_a?(Enumerable) && !a.is_a?(String)
            a = a.to_s
            gen << [:rails_def, kind, a, line]
            gen << [:rails_def, kind, "#{a}=", line]
            if (sing = a.chomp('s')) != a
              # poor man's singularize
              gen << [:rails_def, kind, "#{sing}_ids", line]
              gen << [:rails_def, kind, "#{sing}_ids=", line]
            end
          end
          gen
        when "belongs_to", "has_one"
          a = args[1][0]
          unless a.is_a?(Enumerable) && !a.is_a?(String)
            kind = name.to_sym
            %W[ #{a} #{a}= build_#{a} create_#{a} create_#{a}! ].inject([]) do |all, ident|
              all << [:rails_def, kind, ident, line]
            end
          end
        end
      else
        # super
      end
    end

    private

    def add_variable(name, line, column, scope = @current_scope)
      new_variable = ScopeData::Variable.new(scope, name, line, column)
      scope.variables << new_variable
    end

    def add_ivar(name, line, column)
      scope = @current_scope
      ivar_scope_types = [ScopeData::Base::TYPE_CLASS, ScopeData::Base::TYPE_MODULE]
      while (!ivar_scope_types.include?(scope.type) && !scope.parent.nil?)
        scope = scope.parent
      end
      add_variable(name, line, column, scope)
    end

    def add_scope(args, rest, type)
      (_, name, (line, column)) = args
      push_scope(type, name, line, column)
      process(rest)
      pop_scope()
    end

    def push_scope(type, name, top_line, column)
      close_sibling_scopes(top_line)
      new_scope = ScopeData::Scope.new(@current_scope, type, name, top_line, column)
      @current_scope.children << new_scope
      @current_scope = new_scope
    end

    # This is a very poor man's "end" handler.
    # The notion is that when you start the next scope, all the previous peers and unclosed descendents of the previous peer should be closed.
    def close_sibling_scopes(line)
      parent_scope = @current_scope.parent
      unless (parent_scope.nil?)
        last_sibling = parent_scope.children.last
        while !last_sibling.nil?
          last_sibling.bottom_line = line - 1
          last_sibling = last_sibling.children.last
        end
      end
    end

    def pop_scope
      @current_scope = @current_scope.parent
    end

    def new_root_scope
      ScopeData::Scope.new().tap do |scope|
        scope.type = ScopeData::Scope::TYPE_ROOT
        scope.name = 'Object'
      end
    end
  end


  # This class builds on Ripper's sexp processor to add ruby and rails magic.
  # Specifically it knows about things like alias, attr_*, has_one/many, etc.
  # It adds the appropriate definitions for those magic words.
  class ScopeParser < Ripper
    attr_reader :root_scope

    def initialize(text)
      sexp = self.class.sexp(text)
      processor = SEXPProcessor.new(sexp)
      @root_scope = processor.root_scope
    end

  end

end
