# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::ProjectManager do
  before do
  end

  let(:pm) { RubyLanguageServer::ProjectManager.new('/proj', 'file:///foo/') }

  describe 'ProjectManager' do
    it 'must init' do
      refute_nil(pm)
    end
  end

  describe '#root_path' do
    it 'should set root path once' do
      ENV['RUBY_LANGUAGE_SERVER_PROJECT_ROOT'] = nil
      refute_nil(pm) # Need this to initialize ProjectManager before querying it
      assert_equal('/proj/', RubyLanguageServer::ProjectManager.root_path)
      RubyLanguageServer::ProjectManager.new('/bar')
      assert_equal('/proj/', RubyLanguageServer::ProjectManager.root_path)
    end

    it 'should use the environment variable if set' do
      ENV['RUBY_LANGUAGE_SERVER_PROJECT_ROOT'] = '/proj/'
      assert_equal('/proj/', RubyLanguageServer::ProjectManager.root_path)
      ENV['RUBY_LANGUAGE_SERVER_PROJECT_ROOT'] = nil
    end
  end

  describe '#root_uri' do
    it 'should store a root uri' do
      refute_nil(pm)
      assert_equal('file:///foo/', RubyLanguageServer::ProjectManager.root_uri)
    end
  end

  describe '.install_additional_gems' do
    it 'should deal with nil and blank and space' do
      # There is no refute throws.  So let's just be happy.
      pm.install_additional_gems(nil)
      pm.install_additional_gems([])
      pm.install_additional_gems([''])
    end
  end

  describe '.updated_diagnostics_for_codefile' do
    it 'should call good cop diagnostics' do
      file_content = "# Nothing to see here\n"
      good_mock = MiniTest::Mock.new
      good_mock.expect(:diagnostics, [], [file_content, '/project/boo.rb'])
      RubyLanguageServer::GoodCop.stub(:new, good_mock) do
        cf = RubyLanguageServer::CodeFile.new('file:///foo/boo.rb', file_content)
        pm.updated_diagnostics_for_codefile(cf)
      end
      good_mock.verify
    end
  end

  describe 'has_one' do
    let(:rails_file_text) do
      <<~CODE_FILE
        class Foo < ActiveRecord::Base
          has_one :bar
        end
      CODE_FILE
    end

    it 'should show up as a method' do
      pm.instance_variable_set('@additional_gems_installed', true)
      pm.update_document_content('uri', rails_file_text)
      tags = pm.tags_for_uri('uri')
      bar_tag = tags.detect { |tag| tag[:name] == 'bar' }
      assert_equal('Foo', bar_tag[:containerName])
    end
  end
end
