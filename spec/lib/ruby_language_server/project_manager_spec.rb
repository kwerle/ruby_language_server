require_relative '../../test_helper'
require "minitest/autorun"

describe RubyLanguageServer::ProjectManager do
  before do
  end

  describe "when asked about cheeseburgers" do
    it "must respond positively" do
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
      tags = pm.tags_for_text(rails_file_text, 'uri')
      bar_tag = tags.detect{ |tag| tag[:name] == 'bar' }
      assert_equal("Foo", bar_tag[:containerName])
    end
  end

end
