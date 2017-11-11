module RubyLanguageServer
  module ScopeData
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

      def each(&block)
        self_and_descendants.each{ |member| yield member }
      end

      def self_and_descendants
        [self, children.map(&:self_and_descendants)].flatten
      end

      def self_and_ancestors
        return [self, parent.self_and_ancestors].flatten unless parent.nil?
        self
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
