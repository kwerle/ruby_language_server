require_relative '../../test_helper'
require "minitest/autorun"

describe RubyLanguageServer::CodeFile do
  before do
  end

  describe "CodeFile" do
    it "must init" do
      cf = RubyLanguageServer::CodeFile.new('uri', "class Foo\nend\n")
    end

    describe "tags" do
      def code_file(text)
        RubyLanguageServer::CodeFile.new('uri', text)
      end

      it "should retain existing tags when text becomes unparsable" do
        code_file = code_file("def foo\nend\n")
        assert_equal('foo', code_file.tags.first[:name])
        code_file.text= "def foo\n@foo ||\nend\n"
        assert_equal('foo', code_file.tags.first[:name])
      end

      it "should find functions" do
        tags = code_file("def foo\nend\n").tags
        assert_equal('foo', tags.first[:name])
        assert_equal(6, tags.first[:kind])
      end

      it "should find constants" do
        tags = code_file("FOO=1\n").tags
        assert_equal('FOO', tags.first[:name])
        assert_equal(14, tags.first[:kind])
      end

      it "should not find variables" do
        tags = code_file("@foo=1\n").tags
        assert_equal([], tags)
      end

      it "should do the right thing with self.methods" do
        tags = code_file("def self.foo\nend\n").tags
        assert_equal('foo', tags.first[:name])
        assert_equal(6, tags.first[:kind])
      end

      it "should do the right thing with initialize" do
        tags = code_file("def initialize\nend\n").tags
        assert_equal('initialize', tags.first[:name])
        assert_equal(9, tags.first[:kind])
      end
    end

  end

end
