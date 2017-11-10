require_relative '../../test_helper'
require "minitest/autorun"

describe RubyLanguageServer::CodeFile do
  before do
  end

  describe "when asked about cheeseburgers" do
    it "must respond positively" do
      cf = RubyLanguageServer::CodeFile.new("class Foo\nend\n")
    end
  end

end
