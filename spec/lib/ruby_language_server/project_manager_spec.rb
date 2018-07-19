require_relative '../../test_helper'
require "minitest/autorun"

describe RubyLanguageServer::ProjectManager do
  before do
  end

  describe "ProjectManager" do
    it "must init" do
      pm = RubyLanguageServer::ProjectManager.new("/")
    end
  end

  describe "update_tags" do
    let(:rails_file_text) {
      <<~EOF
        class Foo < ActiveRecord::Base
          has_one :bar
        end
      EOF
    }

    let(:pm) { RubyLanguageServer::ProjectManager.new('foo') }

    it "should have text" do
      pm.update_document_content('uri', rails_file_text)
      tags = pm.tags_for_uri('uri')
      bar_tag = tags.detect{ |tag| tag[:name] == 'bar' }
      assert_equal("Foo", bar_tag[:containerName])
    end
  end

  describe "scope_completions" do

    let(:scopes) {
      scope = RubyLanguageServer::ScopeData::Scope.new
      scope.variables << RubyLanguageServer::ScopeData::Variable.new(scope, 'some_var')
      [scope]
    }

    let(:pm) { RubyLanguageServer::ProjectManager.new('foo') }

    it "should find completions" do
      results = pm.scope_completions('some', scopes)
      assert_equal({"some_var"=>{:depth=>0, :type=>:variable}}, results)
    end

  end

end
