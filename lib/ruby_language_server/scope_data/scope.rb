# frozen_string_literal: true

module RubyLanguageServer
  module ScopeData
    # The Scope class is basically a container with context.
    # It is used to track top & bottom line, variables in this scope, constants, and children - which could be functions, classes, blocks, etc.  Anything that adds scope.
    class Scope < Base
      include Enumerable

      attr_accessor :top_line        # first line
      attr_accessor :bottom_line     # last line
      attr_accessor :depth           # how many parent scopes
      attr_accessor :parent          # parent scope
      attr_accessor :variables       # variables declared in this scope
      attr_accessor :constants       # constants declared in this scope
      attr_accessor :children        # child scopes
      attr_accessor :name            # method
      attr_accessor :superclass_name # superclass name

      def initialize(parent = nil, type = TYPE_ROOT, name = '', top_line = 1, _column = 1)
        super()
        @parent = parent
        @type = type
        @name = name
        @top_line = top_line
        @depth = parent.nil? ? 0 : parent.depth + 1
        @full_name = [parent ? parent.full_name : nil, @name].compact.join(JoinHash[type]) unless type == TYPE_ROOT
        @children = []
        @variables = []
        @constants = []
      end

      def inspect
        "Scope: #{@name} (#{@full_name} - #{@type}) #{@top_line}-#{@bottom_line} children: #{@children} vars: #{@variables}"
      end

      def pretty_print(pp) # rubocop:disable Naming/UncommunicativeMethodParamName
        {
          Scope: {
            type: type,
            name: name,
            lines: [@top_line, @bottom_line],
            children: children,
            variables: variables
          }
        }.pretty_print(pp)
      end

      def full_name
        @full_name || @name
      end

      def has_variable_or_constant?(variable) # rubocop:disable Naming/PredicateName
        test_array = variable.constant? ? constants : variables
        matching_variable = test_array.detect { |test_variable| (test_variable.name == variable.name) }
        !matching_variable.nil?
      end

      # Return the deepest child scopes of this scope - and on up.
      # Not done recuresively because we don't really need to.
      # Normally called on a root scope.
      def scopes_at(position)
        line = position.line
        matching_scopes = select do |scope|
          scope.top_line && scope.bottom_line && (scope.top_line..scope.bottom_line).cover?(line)
        end
        return [] if matching_scopes == []

        deepest_scope = matching_scopes.max_by(&:depth)
        deepest_scope.self_and_ancestors
      end

      def each
        self_and_descendants.each { |member| yield member }
      end

      # Self and all descendents flattened into array
      def self_and_descendants
        [self] + descendants
      end

      def descendants
        children.map(&:self_and_descendants).flatten
      end

      # [self, parent, parent.parent...]
      def self_and_ancestors
        [self, parent&.self_and_ancestors].flatten.compact
      end

      def set_superclass_name(partial)
        if partial.start_with?('::')
          @superclass_name = partial.gsub(/^::/, '')
        else
          @superclass_name = [parent ? parent.full_name : nil, partial].compact.join(JoinHash[type])
        end
      end
    end
  end
end
