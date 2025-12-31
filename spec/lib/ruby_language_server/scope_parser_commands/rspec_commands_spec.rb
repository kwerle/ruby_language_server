# frozen_string_literal: true

require_relative '../../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::ScopeParserCommands::RspecCommands do
  before do
    @code_file_lines = <<-SOURCE
    describe Some::Class do
      let(:foo) { 'bar' }

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
      context 'some context' do
        variable_in_context = 2
      end
    end
    SOURCE
    @parser = RubyLanguageServer::ScopeParser.new(@code_file_lines)
  end

  describe 'blocks' do
    it 'should have a few' do
      assert_equal('describe Some::Class', @parser.root_scope.children.first.name)
      assert_equal(['', 'describe Some::Class', 'block', 'block', 'describe some thing', 'block', 'block', 'describe inner thing', 'block', 'it is happy', 'block', 'it is not sad', 'block', 'context some context', 'block'], @parser.root_scope.self_and_descendants.filter_map(&:name))
    end

    it 'should have a context block' do
      assert_equal(1, @parser.root_scope.children.count)
      top_describe = @parser.root_scope.children.first
      block = top_describe.children.first
      context_block = block.children.last
      assert_equal('context some context', context_block.name)
    end
  end

  describe 'let variables' do
    it 'should capture let variables in the appropriate scope' do
      top_describe = @parser.root_scope.children.first
      block = top_describe.children.first

      # Check that 'foo' variable is in the top describe block
      foo_variable = block.variables.find { |v| v.name == 'foo' }
      refute_nil(foo_variable, 'Expected to find foo variable in top describe block')
      assert_equal(2, foo_variable.line)
    end

    it 'should capture let variables in nested scopes' do
      top_describe = @parser.root_scope.children.first
      block = top_describe.children.first
      some_thing_describe = block.children.find { |c| c.name == 'describe some thing' }
      some_thing_block = some_thing_describe.children.first

      # Check that 'common' variable is in the nested describe block
      common_variable = some_thing_block.variables.find { |v| v.name == 'common' }
      refute_nil(common_variable, 'Expected to find common variable in nested describe block')
      assert_equal(5, common_variable.line)
    end
  end
end
