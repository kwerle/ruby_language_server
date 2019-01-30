# frozen_string_literal: true

module RubyLanguageServer
  module ScopeData
    class Variable < Base
      attr_accessor :line            # line
      attr_accessor :column          # column
      attr_accessor :name            # name
      attr_accessor :full_name       # Module::Class name

      def initialize(scope, name, line = 1, column = 1, type = TYPE_VARIABLE)
        @name = name
        @line = line
        @column = column
        @full_name = [scope.full_name, @name].join(JoinHash[TYPE_VARIABLE])
        @type = type
        raise "bogus variable #{inspect}" unless @name.instance_of? String
      end

      def constant?
        !@name&.match(/^[A-Z]/).nil?
      end
    end
  end
end
