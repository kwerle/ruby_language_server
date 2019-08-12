# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::CodeFile do
  describe 'CodeFile' do
    it 'must init' do
      RubyLanguageServer::CodeFile.build('uri', "class Foo\nend\n")
    end

    describe 'tags' do
      let(:source) do
        <<-SOURCE
        class Foo
          def self.foo_class_method
          end
          def initialize()
          end
          def foo_method
            @foo_ivar = 2
          end
          FOO_CONSTANT = 1
        end
        SOURCE
      end

      let(:tags) { code_file(source).tags }

      def code_file(text)
        RubyLanguageServer::CodeFile.build('uri', text)
      end

      it 'should find classes' do
        code_file = code_file("class Foo\nend\n")
        code_file.tags
        assert_equal(1, code_file.tags.length)
        assert_equal('Foo', code_file.tags.last[:name])
        assert_equal(5, code_file.tags.last[:kind])
      end

      it 'should retain existing tags when text becomes unparsable' do
        code_file = code_file("def foo\nend\n")
        assert_equal('foo', code_file.tags.last[:name])
        code_file.update_text "def foo\n@foo ||\nend\n"
        assert_equal('foo', code_file.tags.last[:name])
      end

      it 'should find functions' do
        tag = tags.detect { |t| t[:name] == 'foo_method' }
        assert_equal(6, tag[:kind])
      end

      it 'should find constants in modules' do
        tag = tags.detect { |t| t[:name] == 'FOO_CONSTANT' }
        assert_equal('FOO_CONSTANT', tag[:name])
        assert_equal(14, tag[:kind])
        assert_equal('Foo', tag[:containerName])
      end

      it 'should not find instance variables' do
        tag = tags.detect { |t| t[:name] == 'foo_ivar' }
        assert_nil(tag)
      end

      it 'should do the right thing with self.methods' do
        tag = tags.detect { |t| t[:name] == 'foo_class_method' }
        assert_equal(6, tag[:kind])
      end

      it 'should do the right thing with initialize' do
        tag = tags.detect { |t| t[:name] == 'initialize' }
        assert_equal(9, tag[:kind])
      end
    end
  end
end
