# frozen_string_literal: true

require_relative '../../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::ScopeParserCommands::RailsCommands do
  before do
    @code_file_lines = <<-SOURCE
      class ModelClass
        has_one :something_else
      end
    SOURCE

    @parser = RubyLanguageServer::ScopeParser.new(@code_file_lines)
  end

  describe 'has_one' do
    it 'should have appropriate functions' do
      class_scope = @parser.root_scope.children.first
      assert_equal(['something_else', 'something_else='], class_scope.children.map(&:name))
    end
  end
end
