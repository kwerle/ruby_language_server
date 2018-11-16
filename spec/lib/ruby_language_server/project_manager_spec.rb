# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::ProjectManager do
  before do
  end

  describe 'ProjectManager' do
    it 'must init' do
      _pm = RubyLanguageServer::ProjectManager.new('/')
    end
  end

  describe 'update_tags' do
    let(:rails_file_text) do
      <<~EOF
        class Foo < ActiveRecord::Base
          has_one :bar
        end
      EOF
    end

    let(:pm) { RubyLanguageServer::ProjectManager.new('foo') }

    it 'should have text' do
      pm.update_document_content('uri', rails_file_text)
      tags = pm.tags_for_uri('uri')
      bar_tag = tags.detect { |tag| tag[:name] == 'bar' }
      assert_equal('Foo', bar_tag[:containerName])
    end
  end
end
