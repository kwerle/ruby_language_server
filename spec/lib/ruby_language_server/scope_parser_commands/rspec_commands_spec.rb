# frozen_string_literal: true

require_relative '../../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::ScopeParserCommands::RspecCommands do
  before do
    @code_file_lines = <<-SOURCE
    describe Some::Class do
      describe 'some thing' do
        let(:common) { 43 }

        describe 'inner thing' do
          it 'is happy' do
            some_var = 1
            assert_equal(1, some_var)
          end
        end

        it 'is not sad' do
          common += 1
          assert_equal(44, common)
        end
      end
    end
    SOURCE
    @parser = RubyLanguageServer::ScopeParser.new(@code_file_lines)
  end

  describe 'blocks' do
    it 'should have a few' do
      assert_equal('describe Some::Class', @parser.root_scope.children.first.name)
      assert_equal(['', 'describe Some::Class', 'block', 'describe some thing', 'block', 'describe inner thing', 'block', 'it is happy', 'block', 'it is not sad', 'block'], @parser.root_scope.self_and_descendants.map(&:name).compact)
    end
  end
end
