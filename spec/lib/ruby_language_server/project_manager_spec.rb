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

end
