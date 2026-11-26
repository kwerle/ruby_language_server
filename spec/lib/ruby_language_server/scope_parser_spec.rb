# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::ScopeParser do
  before do
    @code_file_lines = File.new('spec/fixture_files/scope_parser.sample.rb', 'r').read
  end

  describe 'variables assigned more than once' do
    it 'records only the first assignment in each scope' do
      RubyLanguageServer::ScopeParser.new(<<~RUBY)
        class Foo
          def bar
            x = 1
            x = 2
          end

          def baz
            x = 3
          end
        end
      RUBY

      assert_equal([['x', 3, 'Foo#bar'], ['x', 8, 'Foo#baz']],
                   RubyLanguageServer::ScopeData::Variable.order(:line).map { |v| [v.name, v.line, v.scope.path] })
    end

    it 'does not repeat top-level variables when a parse reuses the root scope' do
      2.times { RubyLanguageServer::ScopeParser.new("top = 1\nclass Foo\nend\n") }

      assert_equal(1, RubyLanguageServer::ScopeData::Variable.where(name: 'top').count)
    end
  end

  describe 'Small file' do
    describe 'normal parsing' do
      before do
        @parser = RubyLanguageServer::ScopeParser.new(@code_file_lines)
      end

      it 'records all the variables' do
        assert_equal(
          RubyLanguageServer::ScopeData::Variable.order(:name).pluck(:name),
          ["@biz", "@bottom", "@niz", "bing", "bogus", "ning", "paf", "par", "par", "pax", "zang", "zing"]
        )
      end

      describe 'class << self' do
        let(:zar) { @parser.root_scope.self_and_descendants.detect { |child| child.full_name == 'Foo::Zar' } }

        it 'should add methods' do
          assert_equal(%w[zoo zor], zar.children.map(&:name).sort)
        end

        it 'marks them as class methods' do
          assert_equal({ 'zoo' => true, 'zor' => true }, zar.children.to_h { |child| [child.name, child.class_method] })
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

    describe 'sibling modules' do
      before do
        @parser = RubyLanguageServer::ScopeParser.new(<<-RUBY)
          module Foo
            module Bar
            end
            module Baz
            end
          end
        RUBY
      end

      it 'places sibling modules at the same level' do
        foo = @parser.root_scope.children.first
        assert_equal('Foo', foo.name)

        children = foo.children
        assert_equal(2, children.size, "Foo should have 2 children, but has #{children.size}")

        bar = children.detect { |c| c.name == 'Bar' }
        baz = children.detect { |c| c.name == 'Baz' }

        refute_nil(bar, "Bar should be a child of Foo")
        refute_nil(baz, "Baz should be a child of Foo")
        assert_equal(0, bar.children.size, "Bar should have no children")
      end
    end

    describe 'sibling classes' do
      before do
        @parser = RubyLanguageServer::ScopeParser.new(<<-RUBY)
          module Foo
            class Bar
            end
            class Baz
            end
          end
        RUBY
      end

      it 'places sibling classes at the same level' do
        foo = @parser.root_scope.children.first
        assert_equal('Foo', foo.name)

        children = foo.children
        assert_equal(2, children.size, "Foo should have 2 children, but has #{children.size}")

        bar = children.detect { |c| c.name == 'Bar' }
        baz = children.detect { |c| c.name == 'Baz' }

        refute_nil(bar, "Bar should be a child of Foo")
        refute_nil(baz, "Baz should be a child of Foo")
        assert_equal(0, bar.children.size, "Bar should have no children")
      end
    end

    describe 'mixed siblings' do
      before do
        @parser = RubyLanguageServer::ScopeParser.new(<<-RUBY)
          module Foo
            class Bar
            end
            module Baz
            end
          end
        RUBY
      end

      it 'places sibling class and module at the same level' do
        foo = @parser.root_scope.children.first
        assert_equal('Foo', foo.name)

        children = foo.children
        assert_equal(2, children.size, "Foo should have 2 children, but has #{children.size}")

        bar = children.detect { |c| c.name == 'Bar' }
        baz = children.detect { |c| c.name == 'Baz' }

        refute_nil(bar, "Bar should be a child of Foo")
        refute_nil(baz, "Baz should be a child of Foo")
        assert_equal(:class, bar.type, "Bar should be a class")
        assert_equal(:module, baz.type, "Baz should be a module")
        assert_equal(0, bar.children.size, "Bar should have no children")
      end
    end

    describe 'module with single constant' do
      before do
        @parser = RubyLanguageServer::ScopeParser.new(<<-RUBY)
          module MyModule
            MY_CONSTANT = 42
          end
        RUBY
      end

      it 'should have the constant as a variable child of the module' do
        my_module = @parser.root_scope.children.first
        assert_equal('MyModule', my_module.name)
        assert_equal(:module, my_module.type, "MyModule should be a module")

        # The constant should be a variable within the module scope
        constant_vars = my_module.variables
        assert_equal(1, constant_vars.size, "MyModule should have 1 constant variable")
        assert_equal('MY_CONSTANT', constant_vars.first.name, "The constant should be named MY_CONSTANT")
      end
    end

    describe 'forwarding parameters' do
      before do
        File.write('test.log', '')
        @parser = RubyLanguageServer::ScopeParser.new(<<-RUBY)
          module RecurringWithConcurrencyJobs
            def perform(...)
            end
          end
        RUBY
      end

      it 'parses module and method scopes' do
        mod = @parser.root_scope.children.first
        refute_nil(mod)
        assert_equal('RecurringWithConcurrencyJobs', mod.name)
        assert_equal('perform', mod.children.first.name)
      end

      it 'does not log parsing exceptions' do
        RubyLanguageServer.logger.instance_variable_get(:@logdev)&.dev&.flush
        refute_match(/Exception in prism parsing/, File.read('test.log'))
      end
    end
  end

  describe 'class << self' do
    it 'marks only the methods directly inside it as class methods' do
      RubyLanguageServer::ScopeParser.new(<<~RUBY)
        class Foo
          class << self
            def make; end

            class Nested
              def instance_method; end
            end
          end

          class << some_object
            def not_ours; end
          end

          def regular; end
        end
      RUBY
      class_methods = RubyLanguageServer::ScopeData::Scope.method_scopes.to_h { |scope| [scope.name, scope.class_method] }

      assert_equal({ 'make' => true, 'instance_method' => false, 'not_ours' => false, 'regular' => false }, class_methods)
    end
  end

  describe 'method parameters' do
    def parameters_of(source)
      RubyLanguageServer::ScopeParser.new(source).root_scope.self_and_descendants.find { |scope| scope.name == 'f' }.parsed_parameters
    end

    it 'keeps every kind in source order, with defaults' do
      parameters = parameters_of("def f(a, (b, c), d = 1, *r, e, f:, g: {x: 1}, **o, &blk)\nend\n")
      assert_equal(
        [
          {'name' => 'a', 'type' => 'required'},
          {'name' => '(b, c)', 'type' => 'required'},
          {'name' => 'd', 'type' => 'optional', 'default' => '1'},
          {'name' => '*r', 'type' => 'rest'},
          {'name' => 'e', 'type' => 'required'},
          {'name' => 'f:', 'type' => 'keyword'},
          {'name' => 'g:', 'type' => 'optional_keyword', 'default' => '{x: 1}'},
          {'name' => '**o', 'type' => 'keyword_rest'},
          {'name' => '&blk', 'type' => 'block'}
        ],
        parameters
      )
    end

    it 'keeps anonymous parameters' do
      assert_equal(%w[* ** &], parameters_of("def f(*, **, &)\nend\n").map { |parameter| parameter['name'] })
    end

    it 'keeps ...' do
      assert_equal([{'name' => '...', 'type' => 'forwarding'}], parameters_of("def f(...)\nend\n"))
    end

    it 'keeps **nil' do
      assert_equal([{'name' => '**nil', 'type' => 'no_keyword'}], parameters_of("def f(**nil)\nend\n"))
    end

    it 'shortens long defaults to one line' do
      default = parameters_of("def f(a = [\n  'one', 'two', 'three', 'four', 'five'\n])\nend\n").first['default']
      assert_equal(30, default.length)
      assert(default.start_with?("[ 'one', 'two'"))
      assert(default.end_with?('…'))
    end

    it 'adds parameters after the rest parameter as variables' do
      RubyLanguageServer::ScopeParser.new("def f(*a, b)\nend\n")
      assert_includes(RubyLanguageServer::ScopeData::Variable.pluck(:name), 'b')
    end
  end

  describe 'documentation' do
    def documentation_of(source, name)
      RubyLanguageServer::ScopeParser.new(source)
      RubyLanguageServer::ScopeData::Scope.find_by(name:).documentation
    end

    it 'stores the comment block directly above a method' do
      assert_equal("Does a thing.\n\nReally.", documentation_of("class Foo\n  # Does a thing.\n  #\n  # Really.\n  def bar\n  end\nend\n", 'bar'))
    end

    it 'ignores a comment separated by a blank line' do
      assert_nil(documentation_of("# Unrelated.\n\ndef bar\nend\n", 'bar'))
    end

    it 'leaves out magic comments and rubocop directives' do
      assert_nil(documentation_of("# frozen_string_literal: true\n# rubocop:disable Style/Foo\nmodule Foo\nend\n", 'Foo'))
    end

    it 'stores the comment above a class or module' do
      assert_equal('The foo.', documentation_of("# The foo.\nmodule Foo\nend\n", 'Foo'))
      assert_equal('The bar.', documentation_of("# The bar.\nclass Bar\nend\n", 'Bar'))
    end
  end
end
