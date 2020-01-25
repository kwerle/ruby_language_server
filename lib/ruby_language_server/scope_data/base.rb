# frozen_string_literal: true

require 'active_record'

module RubyLanguageServer
  module ScopeData
    class Base < ActiveRecord::Base
      self.abstract_class = true

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

      attr_accessor :type # Type of this scope (module, class, block)

      # RubyLanguageServer::ScopeData::Scope.connection.exec_query("SELECT LEVENSHTEIN( 'This is not correct', 'This is correct' )")

      def method?
        type == TYPE_METHOD
      end
    end
  end
end
