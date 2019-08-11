# frozen_string_literal: true

module RubyLanguageServer
  module ScopeData
    class Variable < Base
      belongs_to :scope

      scope :constants, -> { where('name like ?', "#{'A'..'Z'}%") }

      # attr_accessor :line            # line
      # attr_accessor :column          # column
      # attr_accessor :name            # name
      # attr_accessor :path            # Module::Class name

      def self.build(scope, name, line = 1, column = 1, type = TYPE_VARIABLE)
        path = [scope.full_name, name].join(JoinHash[TYPE_VARIABLE])
        create!(
           line: line,
           column: column,
           name: name,
           path: path,
           variable_type: type
        )
        # @name = name
        # @line = line
        # @column = column
        # @full_name =
        # @type = type
        # raise "bogus variable #{inspect}" unless @name.instance_of? String
      end

      def constant?
        !name&.match(/^[A-Z]/).nil?
      end
    end
  end
end
