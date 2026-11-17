# frozen_string_literal: true

require 'sqlite3'
require 'amatch'
require 'active_record/connection_adapters/sqlite3_adapter'

module RubyLanguageServer
  # Defines LEVENSHTEIN(a, b) in Ruby on every SQLite connection, so the server needs no
  # native SQLite extension. Completion ranks names with it (ScopeData::Base.closest_to).
  module SqliteFunctions
    def configure_connection
      super
      @raw_connection.create_function('LEVENSHTEIN', 2) do |function, a, b|
        function.result = a.nil? || b.nil? ? nil : Amatch::Levenshtein.new(a).match(b)
      end
    end
  end
end

ActiveRecord::ConnectionAdapters::SQLite3Adapter.prepend(RubyLanguageServer::SqliteFunctions)
