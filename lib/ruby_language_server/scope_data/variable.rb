# frozen_string_literal: true

require 'active_record'

module RubyLanguageServer
  module ScopeData
    class Variable < Base
      belongs_to :code_file
      belongs_to :scope

      scope :constant_variables, -> { where("SUBSTR(name, 1, 1) between ('A') and ('Z')") }

      delegate :depth, to: :scope

      def self.build(scope, name, line = 1, column = 1, type = TYPE_VARIABLE)
        path = [scope.full_name, name].join(JoinHash[TYPE_VARIABLE])
        create!(
          line: line,
          column: column,
          name: name,
          path: path,
          variable_type: type
        )
      end

      def constant?
        !name&.match(/^[A-Z]/).nil?
      end

      # Convenience for tags
      def top_line
        line
      end
    end
  end
end
