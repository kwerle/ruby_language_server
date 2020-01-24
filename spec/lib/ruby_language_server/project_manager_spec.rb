# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::ProjectManager do
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
    original_root = ENV['RUBY_LANGUAGE_SERVER_PROJECT_ROOT']
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

  describe '.install_additional_gems' do
    it 'should deal with nil and blank and space' do
      # There is no refute throws.  So let's just be happy.
      project_manager.install_additional_gems(nil)
      project_manager.install_additional_gems([])
      project_manager.install_additional_gems([''])
    end
  end

  describe '.updated_diagnostics_for_codefile' do
    it 'should call good cop diagnostics' do
      file_content = "# Nothing to see here\n"
      good_mock = MiniTest::Mock.new
      good_mock.expect(:diagnostics, [], [file_content, '/project/boo.rb'])
      RubyLanguageServer::GoodCop.stub(:new, good_mock) do
        cf = RubyLanguageServer::CodeFile.build('file:///foo/boo.rb', file_content)
        project_manager.updated_diagnostics_for_codefile(cf)
      end
      good_mock.verify
    end
  end

  describe 'has_one' do
    it 'should show up as a method' do
      project_manager.instance_variable_set('@additional_gems_installed', true)
      project_manager.update_document_content('uri', rails_file_text)
      tags = project_manager.tags_for_uri('uri')
      bar_tag = tags.detect { |tag| tag[:name] == 'bar' }
      assert_equal('Foo', bar_tag[:containerName])
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
      assert_equal({isIncomplete: true, items: [{label: 'Bar', kind: 9}, {label: 'bar', kind: 2}, {label: 'bar=', kind: 2}, {label: '@baz', kind: 7}]}, results)
      position = OpenStruct.new(line: 5, character: 4)
      results = project_manager.completion_at('search_uri', position)
      assert_equal({isIncomplete: true, items: [{label: 'Foo', kind: 7}]}, results)
      position = OpenStruct.new(line: 6, character: 4)
      results = project_manager.completion_at('search_uri', position)
      assert_equal({isIncomplete: true, items: [{label: 'Bar', kind: 9}, {label: 'bar', kind: 2}, {label: 'bar=', kind: 2}, {label: '@baz', kind: 7}]}, results)
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

  describe '.scope_definitions_for' do
    it 'lists them appropriately' do
      project_manager.update_document_content('uri', rails_file_text)
      project_manager.scopes_at('uri', OpenStruct.new(line: 1)) # heat up the scopes
      scope = project_manager.all_scopes.find_by(name: :Foo)
      project_manager.scope_definitions_for('bar', scope, 'uri')
      assert_equal([{uri: 'uri', range: {start: {line: 1, character: 1}, end: {line: 1, character: 1}}}], project_manager.scope_definitions_for('@baz', scope, 'uri'))
    end
  end
end
