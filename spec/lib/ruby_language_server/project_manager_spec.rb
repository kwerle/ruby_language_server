# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::ProjectManager do
  before do
  end

  let(:pm) { RubyLanguageServer::ProjectManager.new('/foo') }

  describe 'ProjectManager' do
    it 'must init' do
      refute_nil(pm)
    end
  end

  describe '#root_path' do
    it 'should set root path once' do
      refute_nil(pm)
      assert_equal('/foo', RubyLanguageServer::ProjectManager.root_path)
      RubyLanguageServer::ProjectManager.new('/bar')
      assert_equal('/foo', RubyLanguageServer::ProjectManager.root_path)
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
