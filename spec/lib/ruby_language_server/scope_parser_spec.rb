require_relative '../../test_helper'
require "minitest/autorun"

describe RubyLanguageServer::ScopeParser do
  before do
    @code_file_lines=<<EOF
    module Foo
      class Bar
        attr :top
        def baz(bing, zing)
          zang = 1
          @biz = bing
        end
      end
      class Nar
        def naz(ning)
          @niz = ning
        end
      end
    end
EOF
  end

  describe "ScopeParser" do
    before do
      @parser = RubyLanguageServer::ScopeParser.new(@code_file_lines)
    end

    it "should have a root scope" do
      refute_nil(@parser.root_scope)
    end

    it "should have one module" do
      children = @parser.root_scope.children
      assert_equal(1, children.size)
      m = children.first
      assert_equal('Foo', m.name)
      assert_equal('Foo', m.full_name)
    end

    it "should have two classes" do
      m = @parser.root_scope.children.first
      children = m.children
      assert_equal(2, children.size)
      c1 = children.first
      assert_equal('Bar', c1.name)
      assert_equal('Foo::Bar', c1.full_name)
      c2 = children.last
      assert_equal('Nar', c2.name)
      assert_equal('Foo::Nar', c2.full_name)
    end

    it "should have a function Foo::Bar#baz" do
      m = @parser.root_scope.children.first
      bar = m.children.first
      baz_function = bar.children.first
      assert_equal('baz', baz_function.name)
      assert_equal(3, baz_function.variables.size)
    end

    it "should have a function Foo::Bar#baz" do
      m = @parser.root_scope.children.first
      bar = m.children.first
      baz_function = bar.children.first
      assert_equal('baz', baz_function.name)
      assert_equal(3, baz_function.variables.size)
    end

  end

end
