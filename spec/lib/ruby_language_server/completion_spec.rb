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

  let(:all_scopes) { @scope_parser.root_scope.self_and_descendants }
  let(:nar_naz_scope) { all_scopes.find_by_path('Foo::Nar#naz') }

  def scope_completions(*args)
    RubyLanguageServer::Completion.send(:scope_completions, *args)
  end

  def scope_completions_in_target_context(*args)
    RubyLanguageServer::Completion.send(:scope_completions_in_target_context, *args)
  end

  describe '.completion' do
    it 'does the right thing' do
      context = ['bar', 'ba']
      completions = RubyLanguageServer::Completion.completion(context, nar_naz_scope, all_scopes)
      # Methods with parameters now include insertText, insertTextFormat, label with params, and detail
      expected_items = [
        {label: "Bar", kind: 7},
        {label: "baz(bing, zing)", kind: 2, insertText: "baz(${1:bing}, ${2:zing})", insertTextFormat: 2, detail: "bing (required), zing (required)"}
      ]
      assert_equal(expected_items, completions[:items][0..1])
    end
  end

  describe 'no context' do
    it 'should find the appropriate stuff from inside Foo::Bar' do
      context = ['bog']
      context_scope = all_scopes.find_by(path: 'Foo::Bar')
      position_scopes = @scope_parser.root_scope.self_and_descendants.for_line(context_scope.top_line + 1)
      completions = scope_completions(context.last, position_scopes)
      assert_equal(["bogus", "@bottom"], completions.map(&:first))
    end
  end

  describe 'with context' do
    it 'should find the appropriate stuff from inside Foo::Bar' do
      context = %w[bar ba]
      context_scope = nar_naz_scope
      position_scopes = @scope_parser.root_scope.self_and_descendants.for_line(context_scope.top_line + 1)
      completions = scope_completions_in_target_context(context, context_scope, position_scopes)
      # Sort for consistent comparison since order may vary
      assert_equal(["@biz", "@bottom", "Bar", "Nar", "bar", "baz", "bogus", "naz"], completions.map(&:first).sort)
    end
  end

  describe 'scope_completions' do
    it 'should not leak block variables to the parent scope' do
      context = 'iter'
      context_scope = nar_naz_scope
      position_scopes = @scope_parser.root_scope.self_and_descendants.for_line(context_scope.top_line + 1)
      completions = scope_completions(context, position_scopes)
      assert_equal([], completions.map(&:first))
    end
  end

  describe 'method parameters' do
    before do
      @code_with_params = <<-SOURCE
      class Foo
        def simple_method(arg1, arg2)
        end

        def method_with_keyword(name:, age: 18)
        end

        def method_mixed(required, optional = nil, *rest, keyword:, **kwargs, &block)
        end
      end
      SOURCE
      @parser = RubyLanguageServer::ScopeParser.new(@code_with_params)
    end

    it 'should capture method parameters' do
      simple_method = @parser.root_scope.self_and_descendants.find_by_path('Foo#simple_method')
      params = simple_method.parsed_parameters
      assert_equal(2, params.length)
      assert_equal('arg1', params[0]['name'])
      assert_equal('required', params[0]['type'])
      assert_equal('arg2', params[1]['name'])
      assert_equal('required', params[1]['type'])
    end

    it 'should capture keyword parameters' do
      keyword_method = @parser.root_scope.self_and_descendants.find_by_path('Foo#method_with_keyword')
      params = keyword_method.parsed_parameters
      assert_equal(2, params.length)
      assert_equal('name:', params[0]['name'])
      assert_equal('keyword', params[0]['type'])
      assert_equal('age:', params[1]['name'])
      assert_equal('keyword', params[1]['type'])
    end

    it 'should generate snippet for method with parameters' do
      snippet = RubyLanguageServer::Completion.send(:generate_method_snippet, 'simple_method', [
                                                      { 'name' => 'arg1', 'type' => 'required' },
                                                      { 'name' => 'arg2', 'type' => 'required' }
                                                    ])
      assert_equal('simple_method(${1:arg1}, ${2:arg2})', snippet)
    end

    it 'should generate snippet for method with keyword parameters' do
      snippet = RubyLanguageServer::Completion.send(:generate_method_snippet, 'method_with_keyword', [
                                                      { 'name' => 'name:', 'type' => 'keyword' },
                                                      { 'name' => 'age:', 'type' => 'keyword' }
                                                    ])
      assert_equal('method_with_keyword(name: ${1:value}, age: ${2:value})', snippet)
    end

    it 'should generate snippet for method with mixed parameter types' do
      snippet = RubyLanguageServer::Completion.send(:generate_method_snippet, 'method_mixed', [
                                                      { 'name' => 'required', 'type' => 'required' },
                                                      { 'name' => 'optional', 'type' => 'optional' },
                                                      { 'name' => '*rest', 'type' => 'rest' },
                                                      { 'name' => 'keyword:', 'type' => 'keyword' },
                                                      { 'name' => '**kwargs', 'type' => 'keyword_rest' },
                                                      { 'name' => '&block', 'type' => 'block' }
                                                    ])
      assert_equal('method_mixed(${1:required}, ${2:optional}, ${3:*rest}, keyword: ${4:value}, ${5:**kwargs}, ${6:&block})', snippet)
    end

    it 'should store parameters and generate snippets for methods' do
      all_scopes = @parser.root_scope.self_and_descendants
      simple_method_scope = all_scopes.find_by_path('Foo#simple_method')

      # Test 1: Ensure method has parameters stored
      assert simple_method_scope, 'simple_method scope should exist'
      params = simple_method_scope.parsed_parameters
      assert params.any?, 'simple_method should have parameters'
      assert_equal(2, params.length)
      assert_equal('arg1', params[0]['name'])
      assert_equal('arg2', params[1]['name'])

      # Test 2: Verify snippet generation works with those parameters
      snippet = RubyLanguageServer::Completion.send(:generate_method_snippet, 'simple_method', params)
      assert_equal('simple_method(${1:arg1}, ${2:arg2})', snippet)
    end

    it 'should include parameter information in completion items' do
      all_scopes = @parser.root_scope.self_and_descendants
      foo_scope = all_scopes.find_by_path('Foo')

      # Get completions for 'simple_method'
      completions = RubyLanguageServer::Completion.completion(['simp'], foo_scope, all_scopes)

      # Find the simple_method completion (label now includes parameters)
      simple_method_item = completions[:items].find { |item| item[:label].start_with?('simple_method') }

      assert simple_method_item, 'simple_method should be in completions'
      assert_equal(2, simple_method_item[:kind], 'should be method kind')
      assert_equal('simple_method(arg1, arg2)', simple_method_item[:label], 'should include parameters in label')
      assert_equal('simple_method(${1:arg1}, ${2:arg2})', simple_method_item[:insertText], 'should include parameter snippet')
      assert_equal(2, simple_method_item[:insertTextFormat], 'should be snippet format')
      assert_equal('arg1 (required), arg2 (required)', simple_method_item[:detail], 'should include parameter details')
    end
  end
end
