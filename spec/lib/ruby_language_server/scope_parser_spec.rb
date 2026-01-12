# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::ScopeParser do
  before do
    @code_file_lines = File.new('spec/fixture_files/scope_parser.sample.rb', 'r').read
  end

  describe 'Small file' do
    describe 'shallow parsing' do
      before do
        @parser = RubyLanguageServer::ScopeParser.new(@code_file_lines, true)
      end

      # Life is unfair.  `private` does not start a block - it just sets a flag.  So I may circle back to this.
      # it 'does not find private methods' do
      #   bar = @parser.root_scope.children.first.children.detect { |child| child.full_name == 'Foo::Bar' }
      #   assert_equal(%w[baz], bar.children.map(&:name).sort)
      # end
      it 'does not add any variables at any scope' do
        assert_equal(RubyLanguageServer::ScopeData::Variable.all.count, 0)
      end
    end

    describe 'normal parsing' do
      before do
        @parser = RubyLanguageServer::ScopeParser.new(@code_file_lines)
      end

      it 'records all the variables (as opposed to shallow)' do
        assert_equal(RubyLanguageServer::ScopeData::Variable.order(:name).pluck(:name), [
                       "@biz", "@bottom", "@niz", "bing", "bogus", "ning", "paf", "par", "par", "pax", "zang", "zing"
                     ])
      end

      describe 'class << self' do
        let(:zar) { @parser.root_scope.self_and_descendants.detect { |child| child.full_name == 'Foo::Zar' } }

        it 'should add methods' do
          assert_equal(%w[zoo zor], zar.children.map(&:name).sort)
        end
      end

      describe 'full parsing' do
        it 'finds public and private methods' do
          bar = @parser.root_scope.children.first.children.detect { |child| child.full_name == 'Foo::Bar' }
          assert_equal(%w[baz ding], bar.children.map(&:name).sort)
        end
      end

      it 'has a root scope' do
        refute_nil(@parser.root_scope)
      end

      it 'has one module: Foo' do
        children = @parser.root_scope.children
        assert_equal(1, children.size)
        m = children.first
        assert_equal('Foo', m.name)
        assert_equal('Foo', m.full_name)
      end

      it 'module should span the whole file' do
        m = @parser.root_scope.children.first
        assert_equal(2, m.top_line)
        assert_equal(40, m.bottom_line)
      end

      it 'has two classes' do
        m = @parser.root_scope.children.first
        children = m.children
        assert_equal(3, children.size)
        bar = m.children.detect { |child| child.full_name == 'Foo::Bar' }
        assert_equal('Bar', bar.name)
        assert_equal('Foo::Bar', bar.full_name)
        nar = m.children.detect { |child| child.full_name == 'Foo::Nar' }
        assert_equal('Nar', nar.name)
        assert_equal('Foo::Nar', nar.full_name)
      end

      it 'should see Nar subclasses Bar' do
        m = @parser.root_scope.children.first
        nar = m.children.detect { |child| child.full_name == 'Foo::Nar' }
        assert_equal('Nar', nar.name)
        assert_equal('Foo::Bar', nar.superclass_name)
      end

      it 'has a function Foo::Bar#baz' do
        m = @parser.root_scope.children.first
        bar = m.children.first
        baz_function = bar.children.first
        assert_equal('baz', baz_function.name)
        assert_equal(%w[bing zang zing], baz_function.variables.map(&:name).sort)
      end

      it 'has a couple of ivars for Bar' do
        m = @parser.root_scope.children.first
        bar = m.children.detect { |child| child.full_name == 'Foo::Bar' }
        assert_equal(2, bar.variables.size)
      end

      it 'has a 3 methods for Nar' do
        m = @parser.root_scope.children.first
        nar = m.children.detect { |child| child.full_name == 'Foo::Nar' }
        assert_equal(3, nar.children.size)
        assert_equal(['top', 'top=', 'naz'], nar.children.map(&:name))
      end

      it 'has a couple of ivars for Nar' do
        m = @parser.root_scope.children.first
        bar = m.children.detect { |child| child.full_name == 'Foo::Bar' }
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

    describe 'block with compound variable' do
      let(:block_source) do
        <<-BLOCK
        sum_or_average.each do |(date, c), value|
        end
        BLOCK
      end
      let(:scope_parser) { RubyLanguageServer::ScopeParser.new(block_source) }

      it "should parse the names" do
        block_scope = scope_parser.root_scope.children.first
        assert_equal(1, block_scope.top_line)
        assert_equal(2, block_scope.bottom_line)
        assert_equal(%w[date c value], block_scope.variables.map(&:name))
      end
    end

    describe 'block' do
      let(:block_source) do
        <<-RAKE
        class SomeClass
          def some_method
            # Array of [[object, [key, value]], [object2, [key2, value2]]]
            items.each do |item, (key, value)|
              # should see item as a variable
            end
          end
        end
        RAKE
      end
      let(:scope_parser) { RubyLanguageServer::ScopeParser.new(block_source) }

      it 'should find a block with a variable' do
        assert_equal('item', scope_parser.root_scope.self_and_descendants.last.variables.first.name)
      end
    end

    describe 'siblings' do
      shared_examples 'sibling scopes' do |type|
        it "should place sibling #{type}s at the same level" do
          foo = scope_parser.root_scope.children.first
          assert_equal('Foo', foo.name)

          # Both Bar and Baz should be children of Foo, not Bar containing Baz
          children = foo.children
          assert_equal(2, children.size, "Foo should have 2 children, but has #{children.size}")

          bar = children.detect { |c| c.name == 'Bar' }
          baz = children.detect { |c| c.name == 'Baz' }

          assert_not_nil(bar, "Bar should be a child of Foo")
          assert_not_nil(baz, "Baz should be a child of Foo")

          # Verify Baz is not a child of Bar
          assert_equal(0, bar.children.size, "Bar should have no children, but has #{bar.children.size}")
        end
      end

      describe 'modules' do
        let(:scope_parser) do
          RubyLanguageServer::ScopeParser.new(<<-RUBY)
          module Foo
            module Bar
            end
            module Baz
            end
          end
          RUBY
        end

        include_examples 'sibling scopes', 'module'
      end

      describe 'classes' do
        let(:scope_parser) do
          RubyLanguageServer::ScopeParser.new(<<-RUBY)
          module Foo
            class Bar
            end
            class Baz
            end
          end
          RUBY
        end

        include_examples 'sibling scopes', 'class'
      end

      describe 'mixed (class and module)' do
        let(:scope_parser) do
          RubyLanguageServer::ScopeParser.new(<<-RUBY)
          module Foo
            class Bar
            end
            module Baz
            end
          end
          RUBY
        end

        it 'should place sibling class and module at the same level' do
          foo = scope_parser.root_scope.children.first
          assert_equal('Foo', foo.name)

          # Both Bar (class) and Baz (module) should be children of Foo
          children = foo.children
          assert_equal(2, children.size, "Foo should have 2 children, but has #{children.size}")

          bar = children.detect { |c| c.name == 'Bar' }
          baz = children.detect { |c| c.name == 'Baz' }

          assert_not_nil(bar, "Bar should be a child of Foo")
          assert_not_nil(baz, "Baz should be a child of Foo")

          # Verify types are different
          assert_equal(:class, bar.type, "Bar should be a class")
          assert_equal(:module, baz.type, "Baz should be a module")

          # Verify Baz is not a child of Bar
          assert_equal(0, bar.children.size, "Bar should have no children, but has #{bar.children.size}")
        end
      end
    end
  end
end
