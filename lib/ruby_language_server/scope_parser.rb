require 'ripper'

module RubyLanguageServer

  # This class is responsible for processing the generated sexp from the ScopeParser below.
  # It builds scopes that amount to heirarchical arrays with information about what
  # classes, methods, variables, etc - are in each scope.
  class SEXPProcessor
    attr :sexp
    attr_reader :current_scope
    attr_reader :current_class

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

    def on_assign(args, rest)
      # [:var_field, [:@ident, "zang", [4, 10]]]
      (_, (_, name, (line, column))) = args
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
      # [[:@ident, "bing", [3, 16]], [:@ident, "zing", [3, 22]]]
      args.each do |_, name, (line, column)|
        add_variable(name, line, column)
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
      new_scope = ScopeData::Scope.new(@current_scope, type, name, top_line, column)
      @current_scope.children << new_scope
      @current_scope = new_scope
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
        super
      end
    end

  end
end
