require_relative '../../test_helper'
require "minitest/autorun"

describe RubyLanguageServer::LineContext do
  # before do
  #   @to = RubyLanguageServer::LineContext
  # end

  let(:to) { RubyLanguageServer::LineContext }

  describe "basic variables" do
    let(:line) { 'foo = bar' }

    it "should find 'em'" do
      assert_equal(['foo'], to.for(line, 0))
    end

  end

end
