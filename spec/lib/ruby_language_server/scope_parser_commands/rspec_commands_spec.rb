# frozen_string_literal: true

require_relative '../../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::ScopeParser do
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
      byebug
      assert_equal('11', @parser.root_scope.children.first.name)
      assert_equal(11, @parser.root_scope.children.length)
    end
  end
end
