# frozen_string_literal: true

require_relative '../../test_helper'
require "minitest/autorun"

describe RubyLanguageServer::GoodCop do
  let(:good_cop) { RubyLanguageServer::GoodCop.new() }

  describe 'basics' do
    it 'should init without config' do
      refute_nil(good_cop)
    end
  end

  describe "offenses" do
    it "must lint" do
      offenses = good_cop.send(:offenses, "def BAD\n  true\nend\n", 'whatever.rb')
      assert_equal(['Use snake_case for method names.'], offenses.map(&:message))
    end

    it "must lint two things" do
      offenses = good_cop.send(:offenses, "def BAD\n  fooBar=1\nend\n", 'whatever.rb')
      assert_equal(["Surrounding space missing for operator `=`.", "Useless assignment to variable - `fooBar`.", "Use snake_case for method names.", "Use snake_case for variable names."], offenses.map(&:message))
    end
  end

  describe "diagnostics" do
    it "must lint" do
      diagnostics = good_cop.diagnostics("def BAD\n  true\nend\n", 'foo.rb')
      assert_equal([{:range => {:start => {:line => 0, :character => 4}, :end => {:line => 0, :character => 7}}, :severity => 3, :code => "code", :source => "RuboCop:Naming/MethodName", :message => "Use snake_case for method names."}], diagnostics)
    end
  end
end
