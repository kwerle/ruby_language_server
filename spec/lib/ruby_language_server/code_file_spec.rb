require_relative '../../test_helper'
require "minitest/autorun"

describe RubyLanguageServer::CodeFile do
  before do
  end

  describe "CodeFile" do
    it "must init" do
      cf = RubyLanguageServer::CodeFile.new('uri', "class Foo\nend\n")
    end
  end

end
