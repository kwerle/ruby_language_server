# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::CodeFile do
  before do
  end

  describe 'CodeFile' do
    it 'must init' do
      RubyLanguageServer::CodeFile.new('uri', "class Foo\nend\n")
    end

    describe 'tags' do
      def code_file(text)
        RubyLanguageServer::CodeFile.new('uri', text)
      end

      it "should find classes" do
        code_file = code_file("class Foo\nend\n")
        assert_equal(1, code_file.tags.length)
        assert_equal('Foo', code_file.tags.last[:name])
        assert_equal(5, code_file.tags.last[:kind])
      end

      it 'should retain existing tags when text becomes unparsable' do
        code_file = code_file("def foo\nend\n")
        assert_equal('foo', code_file.tags.last[:name])
        code_file.text = "def foo\n@foo ||\nend\n"
        assert_equal('foo', code_file.tags.last[:name])
      end

      it 'should find functions' do
        tags = code_file("def foo\nend\n").tags
        assert_equal('foo', tags.last[:name])
        assert_equal(6, tags.last[:kind])
      end

      it 'should find constants in modules' do
        tags = code_file("module Parent\nFOO=1\nend\n").tags
        assert_equal('FOO', tags.last[:name])
        assert_equal(14, tags.last[:kind])
      end

      it 'should not find variables' do
        tags = code_file("@foo=1\n").tags
        assert_equal(0, tags.length)
      end

      it 'should do the right thing with self.methods' do
        tags = code_file("def self.foo\nend\n").tags
        assert_equal('foo', tags.last[:name])
        assert_equal(6, tags.last[:kind])
      end

      it 'should do the right thing with initialize' do
        tags = code_file("def initialize\nend\n").tags
        assert_equal('initialize', tags.last[:name])
        assert_equal(9, tags.last[:kind])
      end
    end
  end
end
