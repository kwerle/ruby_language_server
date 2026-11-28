# frozen_string_literal: true

require 'active_record'

module RubyLanguageServer
  module ScopeData
    class Base < ActiveRecord::Base
      self.abstract_class = true

      # Where the record comes from, best first: 0 the project, 1 one of its gems
      # (GemIndex), 2 Ruby core (CoreIndex), which has no file.
      def source_rank
        return 2 if code_file.nil?

        code_file.gem_file? ? 1 : 0
      end

      # The same three sources as queries.
      scope :from_project, -> { joins(:code_file).where(code_files: { gem_name: nil }) }
      scope :from_gems, -> { joins(:code_file).where.not(code_files: { gem_name: nil }) }
      scope :from_core, -> { where(code_file_id: nil) }

      # From a project file, which the editor can open.
      def project_record?
        source_rank.zero?
      end

      TYPE_MODULE = 'module'
      TYPE_CLASS = 'class'
      TYPE_METHOD = 'method'
      TYPE_BLOCK = 'block'
      TYPE_ROOT = 'root'
      TYPE_VARIABLE = 'variable'

      BLOCK_NAME = 'block'

      JoinHash = {
        TYPE_MODULE => '::',
        TYPE_CLASS => '::',
        TYPE_METHOD => '#',
        TYPE_BLOCK => '>',
        TYPE_ROOT => '',
        TYPE_VARIABLE => '^'
      }.freeze

      # Return the class_type as a symbol for easier testing
      def type
        class_type&.to_sym
      end

      # bar should be closer to Bar than Far.  Adding the UPPER version accomplishes this.
      # The word is always passed as a bound value, never interpolated into the SQL.
      scope :with_distance_from, lambda { |word|
        length = word.length
        distance = sanitize_sql_array([
                                        "#{quoted_table_name}.*, LEVENSHTEIN(SUBSTR(#{quoted_table_name}.name, 1, ?), ?) + LEVENSHTEIN(SUBSTR(UPPER(#{quoted_table_name}.name), 1, ?), UPPER(?)) AS levenshtein_distance",
                                        length, word, length, word
                                      ])
        where("LENGTH(#{quoted_table_name}.name) >= ?", length).select(distance)
      }
      scope :closest_to, ->(word) { with_distance_from(word).order(:levenshtein_distance) }

      # RubyLanguageServer::ScopeData::Scope.connection.exec_query("SELECT LEVENSHTEIN( 'This is not correct', 'This is correct' )")

      def method?
        class_type == TYPE_METHOD
      end
    end
  end
end
