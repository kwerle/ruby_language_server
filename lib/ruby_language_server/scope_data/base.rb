# frozen_string_literal: true

module RubyLanguageServer
  module ScopeData
    class Base
      TYPE_MODULE = :module
      TYPE_CLASS = :class
      TYPE_METHOD = :method
      TYPE_BLOCK = :block
      TYPE_ROOT = :root
      TYPE_VARIABLE = :variable

      JoinHash = {
        TYPE_MODULE => '::',
        TYPE_CLASS => '::',
        TYPE_METHOD => '#',
        TYPE_BLOCK => '>',
        TYPE_ROOT => '',
        TYPE_VARIABLE => '^',
      }
      
    end

  end
end
