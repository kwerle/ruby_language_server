# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::Completion do
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
          fake_array.each do |iterator_variable|
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

  let(:Completion) { RubyLanguageServer::Completion }
  let(:all_scopes) { @scope_parser.root_scope.self_and_descendants }
  let(:nar_naz_scope) { all_scopes.find_by_path('Foo::Nar#naz') }

  describe 'no context' do
    it 'should find the appropriate stuff from inside Foo::Bar' do
      context = ['bog']
      context_scope = all_scopes.find_by_path('Foo::Bar')
      position_scopes = @scope_parser.root_scope.self_and_descendants.for_line(context_scope.top_line + 1)
      completions = RubyLanguageServer::Completion.scope_completions(context.last, position_scopes)
      assert_equal(["bogus", "@bottom"], completions.map(&:first))
    end
  end

  describe 'with context' do
    it 'should find the appropriate stuff from inside Foo::Bar' do
      context = %w[bar ba]
      context_scope = nar_naz_scope
      position_scopes = @scope_parser.root_scope.self_and_descendants.for_line(context_scope.top_line + 1)
      completions = RubyLanguageServer::Completion.scope_completions_in_target_context(context, context_scope, position_scopes)
      assert_equal(["bar", "bogus"], completions.map(&:first))
    end
  end

  describe 'scope_completions' do
    it 'should not leak block variables to the parent scope' do
      context = ['iter']
      context_scope = nar_naz_scope
      position_scopes = @scope_parser.root_scope.self_and_descendants.for_line(context_scope.top_line + 1)
      completions = RubyLanguageServer::Completion.scope_completions(context, position_scopes)
      assert_equal([], completions.map(&:first))
    end
  end
end
