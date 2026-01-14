# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::CodeFile do
  describe 'CodeFile' do
    let(:source) do
      <<~SOURCE
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

    def code_file(text)
      RubyLanguageServer::CodeFile.build('uri', text)
    end

    it 'must init' do
      RubyLanguageServer::CodeFile.build('uri', "class Foo\nend\n")
    end

    describe 'tags' do
      let(:tags) { code_file(source).tags }

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

      describe 'location ranges' do
        let(:cf) { code_file(source) }

        it 'should have correct start and end lines for a simple class' do
          tag = cf.tags.detect { |t| t[:name] == 'Foo' }

          # Line numbers are 0-indexed in LSP
          expected_range = {
            start: { line: 0, character: 0 },
            end: { line: 9, character: 0 }
          }
          assert_equal(expected_range, tag[:location][:range])
        end

        it 'should have correct start and end lines for a method' do
          tag = cf.tags.detect { |t| t[:name] == 'foo_method' }

          expected_range = {
            start: { line: 5, character: 2 },
            end: { line: 7, character: 2 }
          }
          assert_equal(expected_range, tag[:location][:range])
        end

        it 'should have correct start and end lines for multiple methods' do
          foo_tag = cf.tags.detect { |t| t[:name] == 'Foo' }
          foo_class_method_tag = cf.tags.detect { |t| t[:name] == 'foo_class_method' }
          initialize_tag = cf.tags.detect { |t| t[:name] == 'initialize' }
          foo_method_tag = cf.tags.detect { |t| t[:name] == 'foo_method' }

          expected_foo_range = {
            start: { line: 0, character: 0 },
            end: { line: 9, character: 0 }
          }
          expected_foo_class_method_range = {
            start: { line: 1, character: 2 },
            end: { line: 2, character: 2 }
          }
          expected_initialize_range = {
            start: { line: 3, character: 2 },
            end: { line: 4, character: 2 }
          }
          expected_foo_method_range = {
            start: { line: 5, character: 2 },
            end: { line: 7, character: 2 }
          }

          assert_equal(expected_foo_range, foo_tag[:location][:range])
          assert_equal(expected_foo_class_method_range, foo_class_method_tag[:location][:range])
          assert_equal(expected_initialize_range, initialize_tag[:location][:range])
          assert_equal(expected_foo_method_range, foo_method_tag[:location][:range])
        end
      end
    end
  end
end
