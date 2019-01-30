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
  let(:nar_naz_scope) { all_scopes.detect { |scope| scope.full_name == 'Foo::Nar#naz' } }

  describe 'no context' do
    it 'should find the appropriate stuff from inside Foo::Bar' do
      context = ['bog']
      context_scope = @scope_parser.root_scope
      completions = RubyLanguageServer::Completion.scope_completions(context.last, context_scope.self_and_ancestors)
      assert_equal(['bogus'], completions.map(&:first))
    end
  end

  describe 'with context' do
    it 'should find the appropriate stuff from inside Foo::Bar' do
      context = %w[bar ba]
      context_scope = nar_naz_scope
      completions = RubyLanguageServer::Completion.scope_completions_in_target_context(context, context_scope, all_scopes)
      assert_equal(['baz', '@biz', '@bottom'], completions.map(&:first))
    end
  end

  describe 'scope_completions' do
    it 'should not leak block variables to the parent scope' do
      context = ['iter']
      context_scope = nar_naz_scope
      completions = RubyLanguageServer::Completion.scope_completions(context, context_scope.self_and_ancestors)
      assert_equal([], completions.map(&:first))
    end
  end
end
