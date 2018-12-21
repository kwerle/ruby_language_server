# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::ScopeParser do
  describe 'Small file' do
    before do
      @code_file_lines = <<-SOURCE
      bogus = Some::Bogus
      module Foo
        class Bar
          @bottom = 1

          public def baz(bing, zing)
            zang = 1
            @biz = bing
          end

        end

        class Nar < Bar
          attr :top

          def naz(ning)
            @niz = ning
          end
        end

      end
      SOURCE
      @parser = RubyLanguageServer::ScopeParser.new(@code_file_lines)
    end

    it 'should have a root scope' do
      refute_nil(@parser.root_scope)
    end

    it 'should have one module' do
      children = @parser.root_scope.children
      assert_equal(1, children.size)
      m = children.first
      assert_equal('Foo', m.name)
      assert_equal('Foo', m.full_name)
    end

    it 'module should span the whole file' do
      m = @parser.root_scope.children.first
      assert_equal(2, m.top_line)
      assert_equal(12, m.bottom_line)
    end

    it 'should have two classes' do
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

    it 'should see Nar subclasses Bar' do
      m = @parser.root_scope.children.first
      children = m.children
      c2 = children.last
      assert_equal('Nar', c2.name)
      assert_equal('Foo::Bar', c2.superclass_name)
    end

    it 'should have a function Foo::Bar#baz' do
      m = @parser.root_scope.children.first
      bar = m.children.first
      baz_function = bar.children.first
      assert_equal('baz', baz_function.name)
      assert_equal(3, baz_function.variables.size)
    end

    it 'should have a couple of ivars for Bar' do
      m = @parser.root_scope.children.first
      bar = m.children.first
      assert_equal(2, bar.variables.size)
    end

    it 'should have a 3 methods for Nar' do
      m = @parser.root_scope.children.first
      bar = m.children.last
      assert_equal(3, bar.children.size)
      assert_equal(['top', 'top=', 'naz'], bar.children.map(&:name))
    end

    it 'should have a couple of ivars for Nar' do
      m = @parser.root_scope.children.first
      bar = m.children.last
      assert_equal(2, bar.variables.size)
    end
  end

  describe 'on_assign' do
    it 'should handle complex lvars' do
      RubyLanguageServer::ScopeParser.new('some.tricky.thing = bob')
    end
  end

  describe 'initialize' do
    it 'should deal with nil' do
      RubyLanguageServer::ScopeParser.new(nil)
    end

    it 'should deal with empty' do
      RubyLanguageServer::ScopeParser.new('')
    end
  end

  describe 'Rakefile' do
    let(:rake_source) do
      <<-RAKE
      desc 'Run guard'
      task guard: [] do
        foo = 1
        `guard`
      end
      RAKE
    end
    let(:scope_parser) { RubyLanguageServer::ScopeParser.new(rake_source) }

    it 'should find a block with a variable' do
      assert_equal('foo', scope_parser.root_scope.self_and_descendants.last.variables.first.name)
    end
  end
end
