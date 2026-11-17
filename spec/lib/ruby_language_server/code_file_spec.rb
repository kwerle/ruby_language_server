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

    describe 'debounced re-parsing' do
      # A file parsed once, that waits `interval` seconds before re-parsing a same-length edit.
      def parsed_file(text, interval:)
        cf = RubyLanguageServer::CodeFile.build('debounce_uri', text)
        cf.define_singleton_method(:reparse_interval) { interval }
        cf.refresh_scopes_if_needed
        cf
      end

      def method_names(code_file)
        code_file.scopes.reload.where(class_type: 'method').pluck(:name)
      end

      it 'waits to re-parse an edit that keeps the line count' do
        cf = parsed_file("class Foo\n  def one; end\nend\n", interval: 60)
        cf.update_text("class Foo\n  def two; end\nend\n")
        cf.refresh_scopes_if_needed

        assert_equal(%w[one], method_names(cf))
        assert(cf.refresh_root_scope, 'still marked for a re-parse')
      end

      it 're-parses at once when the line count changes' do
        cf = parsed_file("class Foo\n  def one; end\nend\n", interval: 60)
        cf.update_text("class Foo\n  def one; end\n  def two; end\nend\n")
        cf.refresh_scopes_if_needed

        assert_equal(%w[one two], method_names(cf).sort)
      end

      it 're-parses once the interval has passed' do
        cf = parsed_file("class Foo\n  def one; end\nend\n", interval: 0.05)
        cf.update_text("class Foo\n  def two; end\nend\n")
        sleep 0.06
        cf.refresh_scopes_if_needed

        assert_equal(%w[two], method_names(cf))
      end
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

      it 'returns an empty list when there is nothing to show' do
        assert_equal([], RubyLanguageServer::CodeFile.build('nil_uri', nil).tags)
        assert_equal([], code_file('').tags)
        assert_equal([], code_file("# just a comment\n").tags)
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

        it 'should have correct start and end lines for constants' do
          tag = cf.tags.detect { |t| t[:name] == 'FOO_CONSTANT' }

          # The constant is on line 9 (1-indexed), which should be line 8 (0-indexed) in LSP
          # FOO_CONSTANT = 1 is on line 9 of the source
          expected_range = {
            start: { line: 8, character: 2 },
            end: { line: 8, character: 2 }
          }
          assert_equal(expected_range, tag[:location][:range])
        end
      end
    end

    describe 'non-ASCII text' do
      it 'reports columns in UTF-16 code units' do
        cf = code_file("class Foo\n  x = '😀é'; BAR = 1\nend\n")
        tag = cf.tags.detect { |t| t[:name] == 'BAR' }
        # BAR is at character 12, UTF-16 code unit 13 and byte 16
        assert_equal(13, tag[:location][:range][:start][:character])
      end

      it 'reads the cursor position as UTF-16 code units' do
        # The cursor is on 'a': character 3, UTF-16 code unit 5. Read as a character
        # index, 5 would land on 'bc'.
        cf = code_file("😀😀 a bc\n")
        assert_equal(%w[a], cf.context_at_location(OpenStruct.new(line: 0, character: 5)))
      end
    end
  end
end
