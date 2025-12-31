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
end
