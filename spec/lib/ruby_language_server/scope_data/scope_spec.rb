# frozen_string_literal: true

require_relative '../../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::ScopeData::Scope do
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
          bar = Bar.new
          @niz = ning
          fake_array.each do |iterator_variable, foo|
            p iterator_variable
          end
        end
      end

    end

    module Bar
      def baz; end
    end
    SOURCE
    @scope_parser = RubyLanguageServer::ScopeParser.new(@code_file_lines)
  end

  let(:root_scope) { @scope_parser.root_scope }
  let(:foo_scope) { @scope_parser.root_scope.self_and_descendants.detect { |scope| scope.name == 'Foo' } }
  let(:bar_class_scope) { @scope_parser.root_scope.self_and_descendants.detect { |scope| scope.name == 'Bar' } }
  let(:baz_method_scope) { @scope_parser.root_scope.self_and_descendants.detect { |scope| scope.name == 'baz' } }
  let(:nar_class_scope) { @scope_parser.root_scope.self_and_descendants.detect { |scope| scope.name == 'Nar' } }
  let(:naz_method_scope) { @scope_parser.root_scope.self_and_descendants.detect { |scope| scope.name == 'naz' } }

  describe 'context helper' do
    it "should show the developer what we're looking at" do
      # @code_file_lines.split("\n").each_with_index { |line, i| p "#{i}: #{line}" }
    end
  end

  describe '.scopes_at' do
    it 'should find the deepest scope' do
      assert_equal([], root_scope.self_and_descendants.for_line(0).where.not(class_type: 'root').to_a)
      assert_equal([], root_scope.self_and_descendants.for_line(1).where.not(class_type: 'root').to_a)
      assert_equal(foo_scope, root_scope.self_and_descendants.for_line(2).by_path_length.first)
      assert_equal(bar_class_scope, root_scope.self_and_descendants.for_line(3).by_path_length.first)
      assert_equal(baz_method_scope, root_scope.self_and_descendants.for_line(6).by_path_length.first)
      assert_equal(nar_class_scope, root_scope.self_and_descendants.for_line(13).by_path_length.first)
      assert_equal(naz_method_scope, root_scope.self_and_descendants.for_line(16).by_path_length.first)
      assert_equal(RubyLanguageServer::ScopeData::Base::TYPE_BLOCK, root_scope.self_and_descendants.for_line(19).by_path_length.first.class_type)
    end
  end

  describe '#descendants' do
    def scopes_for(text, uri)
      code_file = RubyLanguageServer::CodeFile.build(uri, text)
      code_file.refresh_scopes_if_needed
      code_file.scopes
    end

    it 'includes nested scopes but not siblings that share a prefix' do
      scopes = scopes_for(<<~RUBY, 'prefix_uri')
        class Foo
          def baz; end
          class Bar; end
        end
        class FooBar
          def qux; end
        end
      RUBY
      foo = scopes.find_by(path: 'Foo')

      assert_equal(%w[Foo#baz Foo::Bar], foo.descendants.pluck(:path).sort)
      assert_equal(%w[Foo Foo#baz Foo::Bar], foo.self_and_descendants.pluck(:path).sort)
    end

    it 'treats _ and % in the path literally' do
      scopes = scopes_for(<<~RUBY, 'wildcard_uri')
        module A_B
          def inside; end
        end
        module AXB
          def outside; end
        end
      RUBY

      assert_equal(%w[A_B#inside], scopes.find_by(path: 'A_B').descendants.pluck(:path))
    end

    it 'stays in its own file' do
      scopes_for("class Shared\n  def here; end\nend\n", 'here_uri')
      scopes_for("class Shared\n  def there; end\nend\n", 'there_uri')
      here_scopes = RubyLanguageServer::CodeFile.find_by(uri: 'here_uri').scopes

      assert_equal(%w[Shared#here], here_scopes.find_by(path: 'Shared').descendants.pluck(:path))
      assert_equal(%w[Shared Shared#here], here_scopes.root_scope.descendants.pluck(:path).sort)
    end
  end
end
