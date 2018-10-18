# frozen_string_literal: true

module RubyLanguageServer
  module ScopeData
    # The Scope class is basically a container with context.
    # It is used to track top & bottom line, variables in this scope, contanst, and children - which could be functions, classes, blocks, etc.  Anything that adds scope.
    # Remember, this is scope for a file.  It seems reasonabble that this will get used less in the future when we know more about classes.
    class Scope < Base
      include Enumerable

      attr_accessor :top_line        # first line
      attr_accessor :bottom_line     # last line
      attr_accessor :depth           # how many parent scopes
      attr_accessor :parent          # parent scope
      attr_accessor :variables       # variables declared in this scope
      attr_accessor :constants       # constants declared in this scope
      attr_accessor :children        # child scopes
      attr_accessor :type            # Type of this scope (module, class, block)
      attr_accessor :full_name       # Module::Class#method
      attr_accessor :name            # method
      attr_accessor :superclass_name # superclass name

      def initialize(parent = nil, type = TYPE_ROOT, name = '', top_line = 1, column = 1)
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

      # Return the deepest child scopes of this scope - and on up.
      # Not done recuresively because we don't really need to.
      # Normally called on a root scope.
      def scopes_at(position)
        line = position.line
        matching_scopes = select do |scope|
          scope.top_line && scope.bottom_line && (scope.top_line..scope.bottom_line).include?(line)
        end
        return [] if matching_scopes == []
        deepest_scope = matching_scopes.sort_by(&:depth).last
        deepest_scope.self_and_ancestors
      end

      def each(&block)
        self_and_descendants.each{ |member| yield member }
      end

      # Self and all descendents flattened into array
      def self_and_descendants
        [self, children.map(&:self_and_descendants)].flatten
      end

      # [self, parent, parent.parent...]
      def self_and_ancestors
        return [self, parent.self_and_ancestors].flatten unless parent.nil?
        [self]
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
