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

  describe "tags_for_text" do
    let(:pm) { RubyLanguageServer::ProjectManager.new('uri') }

    it "should find functions" do
      tags = pm.tags_for_text('uri', "def foo\nend\n")
      assert_equal('foo', tags.first[:name])
      assert_equal(6, tags.first[:kind])
    end

    it "should find constants" do
      tags = pm.tags_for_text('uri', "FOO=1\n")
      assert_equal('FOO', tags.first[:name])
      assert_equal(14, tags.first[:kind])
    end

    it "should not find variables" do
      tags = pm.tags_for_text('uri', "@foo=1\n")
      assert_nil(tags)
    end

    it "should do the right thing with self.methods" do
      tags = pm.tags_for_text('uri', "def self.foo\nend\n")
      assert_equal('foo', tags.first[:name])
      assert_equal(6, tags.first[:kind])
    end

    it "should do the right thing with initialize" do
      tags = pm.tags_for_text('uri', "def initialize\nend\n")
      assert_equal('initialize', tags.first[:name])
      assert_equal(9, tags.first[:kind])
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
      tags = pm.tags_for_text('uri', rails_file_text)
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
