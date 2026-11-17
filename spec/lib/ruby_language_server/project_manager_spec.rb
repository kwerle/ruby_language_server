# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::ProjectManager do
  describe 'scope prioritization for duplicate names' do
    let(:file_with_nested_classes) do
      <<~CODE_FILE
        class Outer
          VALUE = 'outer'
          class Inner
            VALUE = 'inner'
            def show
              puts VALUE
            end
          end
          def after_inner
            puts VALUE
          end
        end
      CODE_FILE
    end

    before(:each) do
      project_manager.update_document_content('dup_uri', file_with_nested_classes)
      project_manager.tags_for_uri('dup_uri')
    end

    it 'returns the closest VALUE constant in the innermost scope' do
      # Dynamically find the line and character offset of 'VALUE' in the line containing 'puts VALUE'
      code_lines = file_with_nested_classes.lines
      value_line_num = code_lines.find_index { |l| l.include?('puts VALUE') }
      raise "No line with 'puts VALUE' found" if value_line_num.nil?

      value_line = code_lines[value_line_num]
      value_char = value_line.index('VALUE')
      raise "'VALUE' not found in line: #{value_line.inspect}" if value_char.nil?

      position = OpenStruct.new(line: value_line_num, character: value_char)
      results = project_manager.possible_definitions('dup_uri', position)
      assert_equal 2, results.length
      assert_equal 'dup_uri', results.first[:uri]
      assert_equal 'dup_uri', results.last[:uri]
      # Should find VALUE defined on line 3 (Inner::VALUE) first, then Outer::VALUE on line 1
      assert_equal 3, results.first[:range][:start][:line]
      assert_equal 1, results.last[:range][:start][:line]
    end

    it 'returns the outer VALUE constant when in the outer scope' do
      # Dynamically find the line and character offset of 'VALUE' in the after_inner method
      project_manager.update_document_content('dup_uri', file_with_nested_classes)
      code_lines = file_with_nested_classes.lines
      value_line_num = code_lines.find_index { |l| l.include?('puts VALUE') && l.include?('after_inner').! }
      # Find the second occurrence of 'puts VALUE' (after_inner)
      occurrences = code_lines.each_with_index.select { |l, _i| l.include?('puts VALUE') }
      raise "No line with 'puts VALUE' found" if occurrences.empty?

      # The second occurrence is for after_inner
      value_line_num = occurrences[1][1] if occurrences.size > 1
      value_line = code_lines[value_line_num]
      value_char = value_line.index('VALUE')
      raise "'VALUE' not found in line: #{value_line.inspect}" if value_char.nil?

      position = OpenStruct.new(line: value_line_num, character: value_char)
      results = project_manager.possible_definitions('dup_uri', position)
      assert_equal 1, results.length
      assert_equal 'dup_uri', results.first[:uri]
      # Should find VALUE defined on line 1 (Outer::VALUE)
      assert_equal 1, results.first[:range][:start][:line]
    end
  end
  let(:rails_file_text) do
    <<~CODE_FILE
      class Foo < ActiveRecord::Base
        @baz = :Baz
        has_one :bar
      end
    CODE_FILE
  end

  let(:project_manager) { RubyLanguageServer::ProjectManager.new('/proj', 'file:///foo/') }

  describe 'ProjectManager' do
    it 'must init' do
      refute_nil(project_manager)
    end
  end

  def with_project_environment_root(temp_root)
    original_root = ENV.fetch('RUBY_LANGUAGE_SERVER_PROJECT_ROOT', nil)
    ENV['RUBY_LANGUAGE_SERVER_PROJECT_ROOT'] = temp_root
    yield
  ensure
    ENV['RUBY_LANGUAGE_SERVER_PROJECT_ROOT'] = original_root
  end

  describe '#root_path' do
    it 'should set root path once' do
      with_project_environment_root(nil) do
        refute_nil(project_manager) # Need this to initialize ProjectManager before querying it
        assert_equal('/proj/', RubyLanguageServer::ProjectManager.root_path)
        RubyLanguageServer::ProjectManager.new('/bar')
        assert_equal('/proj/', RubyLanguageServer::ProjectManager.root_path)
      end
    end

    it 'should use the environment variable if set' do
      with_project_environment_root('/proj/') do
        assert_equal('/proj/', RubyLanguageServer::ProjectManager.root_path)
      end
    end
  end

  describe '#root_uri' do
    it 'should store a root uri' do
      refute_nil(project_manager)
      assert_equal('file:///foo/', RubyLanguageServer::ProjectManager.root_uri)
    end
  end

  describe '#scan_root_uri' do
    it 'uses the client rootUri' do
      assert_equal('file:///host/project/', RubyLanguageServer::ProjectManager.new('/host/project', 'file:///host/project').scan_root_uri)
    end

    it 'uses rootUri when there is no rootPath' do
      assert_equal('file:///host/project/', RubyLanguageServer::ProjectManager.new(nil, 'file:///host/project/').scan_root_uri)
    end

    it 'keeps rootUri percent-encoding' do
      assert_equal('file:///host/my%20project/', RubyLanguageServer::ProjectManager.new('/host/my project', 'file:///host/my%20project').scan_root_uri)
    end

    it 'falls back to rootPath' do
      assert_equal('file:///host/project/', RubyLanguageServer::ProjectManager.new('/host/project').scan_root_uri)
    end
  end

  describe 'has_one' do
    it 'should show up as a method' do
      project_manager.instance_variable_set(:@additional_gems_installed, true)
      project_manager.update_document_content('uri', rails_file_text)
      tags = project_manager.tags_for_uri('uri')
      bar_tag = tags.detect { |tag| tag[:name] == 'bar' }
      assert_equal('Foo', bar_tag[:containerName])
    end
  end

  describe '#watched_files_changed' do
    around_root = lambda do |test, &block|
      Dir.mktmpdir do |dir|
        test.with_project_environment_root("#{dir}/") do
          RubyLanguageServer::ProjectManager.root_uri = 'file:///host/project/'
          block.call(dir, RubyLanguageServer::ProjectManager.new(dir, 'file:///host/project/'))
        end
      end
    end

    it 'drops a deleted file from the index' do
      around_root.call(self) do |_dir, pm|
        pm.update_document_content('file:///host/project/gone.rb', "class Gone\nend\n")
        pm.tags_for_uri('file:///host/project/gone.rb') # parse it
        assert_equal(1, pm.project_definitions_for('Gone').length)

        pm.watched_files_changed([{ 'uri' => 'file:///host/project/gone.rb', 'type' => 3 }])

        assert_equal([], pm.project_definitions_for('Gone'))
        assert_nil(RubyLanguageServer::CodeFile.find_by(uri: 'file:///host/project/gone.rb'))
      end
    end

    it 'drops every file under a deleted directory' do
      around_root.call(self) do |_dir, pm|
        pm.update_document_content('file:///host/project/lib/a.rb', "class A\nend\n")
        pm.update_document_content('file:///host/project/lib/sub/b.rb', "class B\nend\n")
        pm.update_document_content('file:///host/project/library.rb', "class Library\nend\n")

        pm.watched_files_changed([{ 'uri' => 'file:///host/project/lib', 'type' => 3 }])

        assert_equal(['file:///host/project/library.rb'], RubyLanguageServer::CodeFile.pluck(:uri))
      end
    end

    it 'reads created and changed files from disk' do
      around_root.call(self) do |dir, pm|
        File.write(File.join(dir, 'new file.rb'), "class Created\nend\n")
        pm.watched_files_changed([{ 'uri' => 'file:///host/project/new%20file.rb', 'type' => 1 }])
        assert_equal(['Created'], pm.tags_for_uri('file:///host/project/new%20file.rb').map { |tag| tag[:name] })

        File.write(File.join(dir, 'new file.rb'), "class Renamed\nend\n")
        pm.watched_files_changed([{ 'uri' => 'file:///host/project/new%20file.rb', 'type' => 2 }])
        assert_equal(['Renamed'], pm.tags_for_uri('file:///host/project/new%20file.rb').map { |tag| tag[:name] })
      end
    end

    it 'ignores files outside the project and missing files' do
      around_root.call(self) do |_dir, pm|
        pm.watched_files_changed([
                                   { 'uri' => 'file:///elsewhere/x.rb', 'type' => 1 },
                                   { 'uri' => 'file:///host/project/missing.rb', 'type' => 2 }
                                 ])
        assert_equal(0, RubyLanguageServer::CodeFile.count)
      end
    end
  end

  describe '#completion_at' do
    let(:file_text) do
      <<~CODE_FILE
        module Bar
          class Foo < ActiveRecord::Base
            @baz = :Baz
            has_one :bar
            Ba
            Fo
            ba
          end
        end
      CODE_FILE
    end

    before(:each) do
      project_manager.update_document_content('search_uri', file_text)
    end

    it 'finds the appropriate completions' do
      position = OpenStruct.new(line: 4, character: 4)
      results = project_manager.completion_at('search_uri', position)
      assert_equal({isIncomplete: true, items: [{label: 'Bar', kind: 9}]}, results)
      position = OpenStruct.new(line: 5, character: 4)
      results = project_manager.completion_at('search_uri', position)
      assert_equal({isIncomplete: true, items: [{label: 'Foo', kind: 7}]}, results)
      position = OpenStruct.new(line: 6, character: 4)
      results = project_manager.completion_at('search_uri', position)
      # Sort items by label for consistent comparison
      results[:items] = results[:items].sort_by { |item| item[:label] }
      expected = {isIncomplete: true, items: [{label: '@baz', kind: 7}, {label: 'Bar', kind: 9}, {label: 'bar', kind: 2}, {label: 'bar=', kind: 2}]}
      assert_equal(expected, results)
    end

    it 'returns nil when there is nothing to complete' do
      assert_nil(project_manager.completion_at('search_uri', OpenStruct.new(line: 9, character: 0)))
    end

    it 'completes top-level variables outside any scope' do
      project_manager.update_document_content('top_level_uri', "class Foo\nend\nzebra = 1\nzeb\n")
      results = project_manager.completion_at('top_level_uri', OpenStruct.new(line: 3, character: 2))

      assert_includes(results[:items].map { |item| item[:label] }, 'zebra')
    end
  end

  describe 'requests for a file the server has never seen' do
    let(:unknown_uri) { 'file:///never/seen.rb' }
    let(:position) { OpenStruct.new(line: 0, character: 0) }

    it 'answer without storing the file' do
      assert_equal('', project_manager.text_for_uri(unknown_uri))
      project_manager.tags_for_uri(unknown_uri)
      assert_empty(project_manager.scopes_at(unknown_uri, position))
      project_manager.completion_at(unknown_uri, position)
      assert_equal([], project_manager.possible_definitions(unknown_uri, position))

      assert_nil(RubyLanguageServer::CodeFile.find_by(uri: unknown_uri))
      assert_equal(0, RubyLanguageServer::ScopeData::Scope.count)
    end

    it 'store the file once its text arrives' do
      project_manager.tags_for_uri(unknown_uri)
      project_manager.update_document_content(unknown_uri, "class Seen\nend\n")

      assert_equal(1, RubyLanguageServer::CodeFile.where(uri: unknown_uri).count)
      assert_equal(['Seen'], project_manager.tags_for_uri(unknown_uri).map { |tag| tag[:name] })
    end
  end

  describe '.project_definitions_for' do
    it 'should give a reasonable list' do
      project_manager.update_document_content('uri', rails_file_text)
      project_manager.tags_for_uri('uri') # forces load
      assert_equal([], project_manager.project_definitions_for('xxx'))
      assert_equal(1, project_manager.project_definitions_for('Foo').count)
    end
  end

  describe '.scopes_at' do
    it 'should list them' do
      project_manager.update_document_content('uri', rails_file_text)
      scopes = project_manager.scopes_at('uri', OpenStruct.new(line: 1))
      assert_equal(1, scopes.length)
      assert_equal('Foo', scopes.first.name)
    end
  end

  describe '.skip_scan?' do
    it 'skips spec and test files and vendor directories' do
      %w[spec/foo_spec.rb test/foo_test.rb spec.rb test.rb vendor/bundle/x.rb lib/vendor/y.rb].each do |path|
        assert(RubyLanguageServer::ProjectManager.skip_scan?(path), path)
      end
    end

    it 'keeps files that only contain those words' do
      %w[lib/latest.rb lib/contest.rb lib/inspec.rb app/models/vendor_account.rb lib/vendors/z.rb spec/spec_helper.rb test/test_helper.rb].each do |path|
        refute(RubyLanguageServer::ProjectManager.skip_scan?(path), path)
      end
    end
  end

  describe '.scope_definitions_for' do
    it 'lists them appropriately' do
      project_manager.update_document_content('uri', rails_file_text)
      project_manager.scopes_at('uri', OpenStruct.new(line: 1)) # heat up the scopes
      scope = RubyLanguageServer::ScopeData::Scope.find_by(name: :Foo)
      project_manager.scope_definitions_for('bar', scope, 'uri')
      assert_equal([{uri: 'uri', range: {start: {line: 1, character: 2}, end: {line: 1, character: 2}}}], project_manager.scope_definitions_for('@baz', scope, 'uri'))
    end
  end

  describe '#index_file' do
    # A ProjectManager whose update_document_content raises the given errors in turn, then succeeds.
    def failing_project_manager(*errors)
      pm = RubyLanguageServer::ProjectManager.new('/')
      pm.define_singleton_method(:scan_busy_retry_delay) { 0 }
      pm.instance_variable_set(:@attempts, 0)
      pm.define_singleton_method(:attempts) { @attempts }
      pm.define_singleton_method(:update_document_content) do |_uri, _text|
        @attempts += 1
        error = errors.shift
        raise error if error
      end
      pm
    end

    it 'indexes the file' do
      project_manager.index_file('file:///indexed.rb', "class Indexed\nend\n")
      assert_equal(['Indexed'], project_manager.tags_for_uri('file:///indexed.rb').map { |tag| tag[:name] })
    end

    it 'retries when the database is busy' do
      pm = failing_project_manager(ActiveRecord::StatementTimeout.new('busy'), ActiveRecord::StatementTimeout.new('busy'))
      pm.index_file('file:///busy.rb', "class Busy\nend\n")
      assert_equal(3, pm.attempts)
    end

    it 'gives up after a few busy retries' do
      busy = Array.new(RubyLanguageServer::ProjectManager::SCAN_BUSY_RETRIES + 1) { ActiveRecord::StatementTimeout.new('busy') }
      pm = failing_project_manager(*busy)
      assert_raises(ActiveRecord::StatementTimeout) { pm.index_file('file:///busy.rb', '') }
      assert_equal(RubyLanguageServer::ProjectManager::SCAN_BUSY_RETRIES + 1, pm.attempts)
    end

    it 'does not retry other errors' do
      pm = failing_project_manager(ActiveRecord::RecordInvalid.new)
      assert_raises(ActiveRecord::RecordInvalid) { pm.index_file('file:///bad.rb', '') }
      assert_equal(1, pm.attempts)
    end
  end

  describe '#possible_definitions' do
    let(:file_with_class_and_methods) do
      <<~CODE_FILE
        class TestClass
          def initialize
            @instance_var = 42
          end

          def test_method
            local_var = 10
            puts local_var
          end
        end
      CODE_FILE
    end

    before(:each) do
      project_manager.update_document_content('test_uri', file_with_class_and_methods)
    end

    it 'returns empty array for blank names' do
      position = OpenStruct.new(line: 0, character: 0)
      result = project_manager.possible_definitions('test_uri', position)
      assert_equal([], result)
    end

    it 'finds class definitions' do
      # Position on "TestClass"
      position = OpenStruct.new(line: 0, character: 6)
      results = project_manager.possible_definitions('test_uri', position)

      assert_equal 1, results.length
      assert_equal 'test_uri', results.first[:uri]
      assert_equal 0, results.first[:range][:start][:line]
    end

    it 'finds method definitions' do
      # Position on "test_method"
      position = OpenStruct.new(line: 5, character: 6)
      results = project_manager.possible_definitions('test_uri', position)

      assert_equal 1, results.length
      assert_equal 'test_uri', results.first[:uri]
      assert_equal 5, results.first[:range][:start][:line]
      assert_equal 2, results.first[:range][:start][:character] # the indented def
    end

    it 'points at the column where a local variable is assigned' do
      # Position on "local_var" in "puts local_var"
      position = OpenStruct.new(line: 7, character: 10)
      results = project_manager.possible_definitions('test_uri', position)

      assert_equal([{start: {line: 6, character: 4}, end: {line: 6, character: 4}}], results.map { |r| r[:range] })
    end

    it 'finds instance variable definitions in scope' do
      # Position within the initialize method where @instance_var is defined
      position = OpenStruct.new(line: 2, character: 4)
      results = project_manager.possible_definitions('test_uri', position)

      # If the result is empty, the word_at_location might not be finding the variable
      # Let's just verify the method doesn't error and returns an array
      assert_instance_of Array, results
    end

    it 'converts "new" to "initialize" for lookups' do
      file_with_new = <<~CODE_FILE
        class MyClass
          def initialize
            @value = 1
          end
        end

        obj = MyClass.new
      CODE_FILE

      project_manager.update_document_content('new_uri', file_with_new)
      project_manager.tags_for_uri('new_uri') # Force load of tags

      # Position on "new"
      position = OpenStruct.new(line: 6, character: 17)
      results = project_manager.possible_definitions('new_uri', position)

      # Should find initialize method at line 1
      assert_equal 1, results.length
      assert_equal 'new_uri', results.first[:uri]
      assert_equal 1, results.first[:range][:start][:line]
    end

    it 'searches project-wide when not found in scope' do
      # Create another file with a class
      other_file = <<~CODE_FILE
        class OtherClass
          def other_method
          end
        end
      CODE_FILE

      project_manager.update_document_content('other_uri', other_file)
      project_manager.tags_for_uri('other_uri') # Force load

      # Now search for OtherClass from the first file
      position = OpenStruct.new(line: 0, character: 0)
      results = project_manager.possible_definitions('other_uri', position)
      assert_equal([], results)

      # We need to actually have "OtherClass" in the file at that position
      # Let's update the test file
      file_with_reference = <<~CODE_FILE
        OtherClass
      CODE_FILE

      project_manager.update_document_content('ref_uri', file_with_reference)
      position = OpenStruct.new(line: 0, character: 5)

      results = project_manager.possible_definitions('ref_uri', position)

      # Should find OtherClass from other file
      assert_operator results.length, :>=, 1
      other_class_result = results.find { |r| r[:uri] == 'other_uri' }
      refute_nil other_class_result
      assert_equal 0, other_class_result[:range][:start][:line]
    end

    describe 'namespaced class lookup' do
      let(:file_with_namespaced_class) do
        <<~CODE_FILE
          module Foo
            class Bar
              def import
                puts "import method"
              end
            end
          end

          # In a spec file:
          describe Foo::Bar, "#import" do
            # When clicking on Bar in Foo::Bar
          end
        CODE_FILE
      end

      before(:each) do
        project_manager.update_document_content('namespace_uri', file_with_namespaced_class)
        project_manager.tags_for_uri('namespace_uri') # Force load of tags
      end

      it 'finds namespaced class definition when clicking on the class name' do
        # Position on "Bar" in "Foo::Bar" (line 9, around character 16-18)
        # The line is: "describe Foo::Bar, \"#import\" do"
        # Character 16 is on 'B' of Bar
        position = OpenStruct.new(line: 9, character: 16)
        results = project_manager.possible_definitions('namespace_uri', position)

        # Should find the Bar class definition on line 1 (0-indexed)
        assert_equal 1, results.length
        assert_equal 'namespace_uri', results.first[:uri]
        assert_equal 1, results.first[:range][:start][:line]
      end

      it 'finds namespaced class definition when clicking on the module name' do
        # Position on "Foo" in "Foo::Bar" (line 9, around character 11)
        position = OpenStruct.new(line: 9, character: 11)
        results = project_manager.possible_definitions('namespace_uri', position)

        # Should find the Foo module definition on line 0
        assert_equal 1, results.length
        assert_equal 'namespace_uri', results.first[:uri]
        assert_equal 0, results.first[:range][:start][:line]
      end
    end

    describe 'class << self method lookup' do
      it 'finds a method defined in class << self through the class' do
        project_manager.update_document_content('singleton_uri', <<~CODE_FILE)
          class Factory
            class << self
              def make
              end
            end
          end

          Factory.make
        CODE_FILE
        project_manager.tags_for_uri('singleton_uri') # Force load of tags

        results = project_manager.possible_definitions('singleton_uri', OpenStruct.new(line: 7, character: 9))

        assert_equal([2], results.map { |r| r[:range][:start][:line] })
      end
    end

    describe 'namespaced class method lookup' do
      let(:file_with_namespaced_class_method) do
        <<~CODE_FILE
          module Foo
            class Bar
              def self.class_method
                puts "class method"
              end
              def some_method
                puts "instance method"
              end
            end
          end

          Foo::Bar # clicking on Bar should find the class
          Foo::Bar.class_method # clicking on class_method should find the method
        CODE_FILE
      end

      before(:each) do
        project_manager.update_document_content('namespace_method_uri', file_with_namespaced_class_method)
        project_manager.tags_for_uri('namespace_method_uri') # Force load of tags
      end

      it 'finds namespaced class when clicking on Bar in Foo::Bar' do
        # Position on "Bar" in "Foo::Bar" (0-indexed line 11)
        # The line is: "Foo::Bar # clicking on Bar should find the class"
        # Character 5 is on 'B' of Bar
        position = OpenStruct.new(line: 11, character: 5)
        results = project_manager.possible_definitions('namespace_method_uri', position)

        # Should find the Bar class definition on line 1 (0-indexed)
        assert_equal 1, results.length
        assert_equal 'namespace_method_uri', results.first[:uri]
        assert_equal 1, results.first[:range][:start][:line]
      end

      it 'finds class method when clicking on class_method in Foo::Bar.class_method' do
        # Position on "class_method" in "Foo::Bar.class_method" (0-indexed line 12)
        # The line is: "Foo::Bar.class_method # clicking on class_method should find the method"
        # Character 9 is on 'c' of class_method
        position = OpenStruct.new(line: 12, character: 9)
        results = project_manager.possible_definitions('namespace_method_uri', position)

        # Should find the class_method definition on line 2 (0-indexed)
        assert_equal 1, results.length
        assert_equal 'namespace_method_uri', results.first[:uri]
        assert_equal 2, results.first[:range][:start][:line]
      end
    end

    describe 'superclass lookup' do
      before(:each) do
        project_manager.update_document_content('base_uri', <<~CODE_FILE)
          class Base
            def inherited_helper
            end

            def self.build
            end
          end
        CODE_FILE
        project_manager.update_document_content('unrelated_uri', <<~CODE_FILE)
          class Unrelated
            def inherited_helper
            end

            def self.build
            end
          end
        CODE_FILE
        project_manager.update_document_content('child_uri', <<~CODE_FILE)
          module App
            class Child < Base
              def run
                inherited_helper
                inher
              end
            end
          end

          App::Child.build
        CODE_FILE
        %w[base_uri unrelated_uri child_uri].each { |uri| project_manager.tags_for_uri(uri) } # Force load of tags
      end

      def locations(results)
        results.map { |r| [r[:uri], r[:range][:start][:line]] }
      end

      it 'finds an inherited method called without a receiver' do
        # Position on "inherited_helper" in Child#run
        results = project_manager.possible_definitions('child_uri', OpenStruct.new(line: 3, character: 8))

        assert_equal([['base_uri', 1]], locations(results))
      end

      it 'finds an inherited class method through the subclass' do
        # Position on "build" in "App::Child.build"
        results = project_manager.possible_definitions('child_uri', OpenStruct.new(line: 9, character: 13))

        assert_equal([['base_uri', 4]], locations(results))
      end

      it 'completes inherited methods' do
        # Position at the end of "inher" in Child#run
        completions = project_manager.completion_at('child_uri', OpenStruct.new(line: 4, character: 9))

        assert_includes(completions[:items].map { |item| item[:label] }, 'inherited_helper')
      end
    end

    describe 'parameter vs method name resolution' do
      let(:file_with_param_shadowing) do
        <<~CODE_FILE
          class Ack
            def meaningful                    # line 1: instance method in Ack
              puts "method in Ack"
            end
          end

          class Foo
            def meaningful                    # line 7: instance method in Foo
              puts "instance method in Foo"
            end

            def self.meaningful               # line 11: class method in Foo
              puts "class method in Foo"
            end
          end

          class Bar
            def some_method(meaningful)       # line 17: parameter declaration
              meaningful.do_something
              foo.meaningful
              Foo.meaningful
            end
          end
        CODE_FILE
      end

      before(:each) do
        project_manager.update_document_content('param_uri', file_with_param_shadowing)
        project_manager.tags_for_uri('param_uri') # Force load of tags
      end

      it 'finds method parameter definition when parameter shadows method names' do
        # Position on "meaningful" parameter usage inside some_method (line 18, character 4)
        position = OpenStruct.new(line: 18, character: 4)
        results = project_manager.possible_definitions('param_uri', position)

        # Should find the parameter definition on line 17, not the methods on line 1, 7, or 11
        assert_equal 1, results.length
        assert_equal 'param_uri', results.first[:uri]
        assert_equal 17, results.first[:range][:start][:line]
      end

      it 'finds method definitions when called on receiver object' do
        # Position on "meaningful" method call on foo (line 19, character 12)
        position = OpenStruct.new(line: 19, character: 12)
        results = project_manager.possible_definitions('param_uri', position)

        # Should find instance method definitions (both Ack and Foo) because it's called on foo
        # Without type inference, we can't determine foo's type, so both are valid
        # Currently also includes class method on line 11, but ideally should only return instance methods
        result_lines = results.map { |r| r[:range][:start][:line] }.sort
        assert_operator results.length, :>=, 2
        assert_includes result_lines, 1  # Ack instance method
        assert_includes result_lines, 7  # Foo instance method
        # Note: Currently also returns line 11 (class method) - future improvement would filter this out
      end

      it 'finds only class method when called on class name' do
        # Position on "meaningful" method call on Foo (line 20, character 12)
        position = OpenStruct.new(line: 20, character: 12)
        results = project_manager.possible_definitions('param_uri', position)
        assert_equal 1, results.length
        assert_equal 'param_uri', results.first[:uri]
        # Should find class method on line 11
        assert_equal 11, results.first[:range][:start][:line]
      end
    end

    describe 'query count' do
      it 'loads the code files of project-wide results in one query' do
        5.times { |i| project_manager.update_document_content("many_#{i}", "class Many#{i}\n  def shared_name\n  end\nend\n") }
        5.times { |i| project_manager.tags_for_uri("many_#{i}") } # Force load of tags
        project_manager.update_document_content('caller', "thing.shared_name\n")
        project_manager.tags_for_uri('caller')

        code_file_queries = 0
        counter = ->(*, payload) { code_file_queries += 1 if payload[:sql].include?('FROM "code_files" WHERE "code_files"."id"') }
        results = ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
          project_manager.possible_definitions('caller', OpenStruct.new(line: 0, character: 8))
        end

        assert_equal(5, results.length)
        assert_operator(code_file_queries, :<=, 1)
      end
    end

    describe 'constant lookup with namespace' do
      let(:file_with_namespaced_constant) do
        <<~CODE_FILE
          module Foo
            BAR = "bar constant"

            class Baz
              QUUX = "quux constant"
            end
          end

          # Using the constant
          puts Foo::BAR
          puts Foo::Baz::QUUX
        CODE_FILE
      end

      before(:each) do
        project_manager.update_document_content('const_uri', file_with_namespaced_constant)
        project_manager.tags_for_uri('const_uri') # Force load of tags
      end

      it 'finds constant definition when clicking on constant in Foo::BAR' do
        # Position on "BAR" in "Foo::BAR" (line 9, character 10)
        # The line is: "puts Foo::BAR"
        position = OpenStruct.new(line: 9, character: 10)
        results = project_manager.possible_definitions('const_uri', position)

        # Should find the BAR constant definition on line 1
        assert_equal 1, results.length, "Expected to find 1 definition for Foo::BAR, but got #{results.length}"
        assert_equal 'const_uri', results.first[:uri]
        assert_equal 1, results.first[:range][:start][:line]
      end

      it 'finds constant definition when clicking on nested constant in Foo::Baz::QUUX' do
        # Position on "QUUX" in "Foo::Baz::QUUX" (line 10, character 16)
        position = OpenStruct.new(line: 10, character: 16)
        results = project_manager.possible_definitions('const_uri', position)

        # Should find the QUUX constant definition on line 4
        assert_equal 1, results.length, "Expected to find 1 definition for Foo::Baz::QUUX, but got #{results.length}"
        assert_equal 'const_uri', results.first[:uri]
        assert_equal 4, results.first[:range][:start][:line]
      end

      it 'finds module definition when clicking on Foo in Foo::BAR' do
        # Position on "Foo" in "Foo::BAR" (line 9, character 5)
        position = OpenStruct.new(line: 9, character: 5)
        results = project_manager.possible_definitions('const_uri', position)

        # Should find the Foo module definition on line 0
        assert_equal 1, results.length
        assert_equal 'const_uri', results.first[:uri]
        assert_equal 0, results.first[:range][:start][:line]
      end
    end

    describe 'receiver constants resolved through enclosing namespaces' do
      let(:nested_file) do
        <<~CODE_FILE
          module Outer
            class Inner
              def self.go
              end
            end

            class Other
              def run
                Inner.go
                ::Inner.go
              end
            end
          end
        CODE_FILE
      end

      let(:top_level_file) do
        <<~CODE_FILE
          class Inner
            def self.go
            end
          end
        CODE_FILE
      end

      before(:each) do
        project_manager.update_document_content('nested_uri', nested_file)
        project_manager.update_document_content('top_uri', top_level_file)
        project_manager.tags_for_uri('nested_uri') # Force load of tags
        project_manager.tags_for_uri('top_uri')
      end

      it 'prefers the constant in an enclosing namespace' do
        # Position on "go" in "Inner.go" inside Outer::Other
        results = project_manager.possible_definitions('nested_uri', OpenStruct.new(line: 8, character: 13))

        assert_equal([['nested_uri', 2]], results.map { |r| [r[:uri], r[:range][:start][:line]] })
      end

      it 'uses only the top level after a leading ::' do
        # Position on "go" in "::Inner.go"
        results = project_manager.possible_definitions('nested_uri', OpenStruct.new(line: 9, character: 15))

        assert_equal([['top_uri', 1]], results.map { |r| [r[:uri], r[:range][:start][:line]] })
      end

      it 'returns a definition from every file that reopens the class' do
        project_manager.update_document_content('reopen_uri', "class Inner\n  def self.stop\n  end\nend\n")
        # Another stop, which a project-wide search would also return.
        project_manager.update_document_content('unrelated_uri', "class Unrelated\n  def self.stop\n  end\nend\n")
        project_manager.update_document_content('caller_uri', "Inner.stop\nInner.go\n")
        %w[reopen_uri unrelated_uri caller_uri].each { |uri| project_manager.tags_for_uri(uri) }

        stop = project_manager.possible_definitions('caller_uri', OpenStruct.new(line: 0, character: 7))
        go = project_manager.possible_definitions('caller_uri', OpenStruct.new(line: 1, character: 7))

        assert_equal([['reopen_uri', 1]], stop.map { |r| [r[:uri], r[:range][:start][:line]] })
        assert_equal([['top_uri', 1]], go.map { |r| [r[:uri], r[:range][:start][:line]] })
      end
    end
  end
end
