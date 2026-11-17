# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::Server do
  let(:mutex) { Mutex.new }
  let(:server) { RubyLanguageServer::Server.new(mutex) }

  describe '#initialize' do
    it 'initializes with a mutex' do
      refute_nil(server)
      assert_instance_of Mutex, mutex
    end
  end

  describe '#on_initialize' do
    let(:params) do
      {
        'rootPath' => '/test/project',
        'rootUri' => 'file:///test/project'
      }
    end

    it 'returns capabilities hash' do
      result = server.on_initialize(params)

      refute_nil(result)
      assert_includes result.keys, :capabilities

      capabilities = result[:capabilities]
      assert_equal %i[textDocumentSync definitionProvider documentSymbolProvider hoverProvider completionProvider].sort,
                   capabilities.keys.sort
      assert_equal 1, capabilities[:textDocumentSync]
      assert_equal true, capabilities[:definitionProvider]
      assert_equal true, capabilities[:documentSymbolProvider]
    end

    it 'reports serverInfo with the gem version' do
      result = server.on_initialize(params)

      assert_equal({ name: 'ruby_language_server', version: RubyLanguageServer::VERSION }, result[:serverInfo])
    end

    it 'sets up completion provider without resolve' do
      result = server.on_initialize(params)

      completion = result[:capabilities][:completionProvider]
      refute_nil(completion)
      refute completion.key?(:resolveProvider), 'there is no completionItem/resolve handler'
      assert_equal ['.', '::'], completion[:triggerCharacters]
    end

    it 'has a handler for every advertised capability' do
      handlers = {
        textDocumentSync: %i[on_textDocument_didOpen on_textDocument_didChange],
        definitionProvider: %i[on_textDocument_definition],
        documentSymbolProvider: %i[on_textDocument_documentSymbol],
        hoverProvider: %i[on_textDocument_hover],
        completionProvider: %i[on_textDocument_completion]
      }
      server.on_initialize(params)[:capabilities].each_key do |capability|
        assert handlers.key?(capability), "#{capability} is advertised; add its handlers to this test"
        handlers[capability].each do |handler|
          assert server.respond_to?(handler), "#{capability} is advertised but Server has no #{handler}"
        end
      end
    end

    it 'initializes project manager with root path and uri' do
      server.on_initialize(params)

      project_manager = server.instance_variable_get(:@project_manager)
      refute_nil(project_manager)
      assert_instance_of RubyLanguageServer::ProjectManager, project_manager
    end
  end

  describe '#on_initialized' do
    it 'logs version information' do
      server.on_initialized({})
      # Just verify it doesn't raise an error
      assert true
    end
  end

  describe '#on_workspace_didChangeWatchedFiles' do
    it 'returns nil' do
      params = { 'changes' => [] }
      result = server.on_workspace_didChangeWatchedFiles(params)

      assert_equal({}, result)
    end
  end

  describe '#on_textDocument_hover' do
    before do
      server.on_initialize({ 'rootPath' => '/test/project', 'rootUri' => 'file:///test/project' })
    end

    it 'returns nil when there is nothing under the cursor' do
      server.instance_variable_get(:@project_manager).update_document_content('file:///test.rb', "\n")
      params = {
        'textDocument' => { 'uri' => 'file:///test.rb' },
        'position' => { 'line' => 0, 'character' => 0 }
      }
      result = server.on_textDocument_hover(params)

      assert_nil result
    end

    it 'returns markdown for a method' do
      project_manager = server.instance_variable_get(:@project_manager)
      project_manager.update_document_content('file:///hover.rb', "class Foo\n  def bar(a)\n  end\nend\nfoo.bar(1)\n")
      project_manager.tags_for_uri('file:///hover.rb') # parse it
      params = {
        'textDocument' => { 'uri' => 'file:///hover.rb' },
        'position' => { 'line' => 4, 'character' => 5 }
      }
      result = server.on_textDocument_hover(params)

      assert_equal 'markdown', result[:contents][:kind]
      assert_includes result[:contents][:value], 'def bar(a)'
    end
  end

  describe '#on_textDocument_documentSymbol' do
    before do
      params = {
        'rootPath' => '/test/project',
        'rootUri' => 'file:///test/project'
      }
      server.on_initialize(params)
    end

    it 'returns symbols for a document' do
      params = {
        'textDocument' => { 'uri' => 'file:///test.rb' }
      }

      project_manager = server.instance_variable_get(:@project_manager)
      def project_manager.tags_for_uri(_uri)
        [{ name: 'TestClass', kind: 'class' }]
      end

      result = server.on_textDocument_documentSymbol(params)

      refute_nil(result)
      assert_equal [{ name: 'TestClass', kind: 'class' }], result
    end
  end

  describe '#on_textDocument_definition' do
    before do
      params = {
        'rootPath' => '/test/project',
        'rootUri' => 'file:///test/project'
      }
      server.on_initialize(params)
    end

    it 'returns possible definitions' do
      params = {
        'textDocument' => { 'uri' => 'file:///test.rb' },
        'position' => { 'line' => 5, 'character' => 10 }
      }

      project_manager = server.instance_variable_get(:@project_manager)
      def project_manager.possible_definitions(_uri, _position)
        [{ uri: 'file:///test.rb', range: {} }]
      end

      result = server.on_textDocument_definition(params)

      refute_nil(result)
      assert_equal [{ uri: 'file:///test.rb', range: {} }], result
    end
  end

  describe '#on_textDocument_didOpen' do
    before do
      params = {
        'rootPath' => '/test/project',
        'rootUri' => 'file:///test/project'
      }
      server.on_initialize(params)
    end

    it 'sends diagnostics for opened document' do
      # Create a simple test double for IO
      captured_method = nil
      captured_args = nil
      test_io = Object.new
      test_io.define_singleton_method(:send_notification) do |method, args|
        captured_method = method
        captured_args = args
      end
      server.io = test_io

      params = {
        'textDocument' => {
          'uri' => 'file:///test.rb',
          'text' => 'class Foo\nend'
        }
      }

      server.on_textDocument_didOpen(params)

      assert_equal 'textDocument/publishDiagnostics', captured_method
      assert_equal 'file:///test.rb', captured_args[:uri]
      assert captured_args.key?(:diagnostics)
    end
  end

  describe '#on_textDocument_didChange' do
    before do
      params = {
        'rootPath' => '/test/project',
        'rootUri' => 'file:///test/project'
      }
      server.on_initialize(params)
    end

    it 'sends diagnostics for changed document' do
      # Create a simple test double for IO
      captured_method = nil
      captured_args = nil
      test_io = Object.new
      test_io.define_singleton_method(:send_notification) do |method, args|
        captured_method = method
        captured_args = args
      end
      server.io = test_io

      params = {
        'textDocument' => { 'uri' => 'file:///test.rb' },
        'contentChanges' => [
          { 'text' => 'class Bar\nend' }
        ]
      }

      server.on_textDocument_didChange(params)

      assert_equal 'textDocument/publishDiagnostics', captured_method
      assert_equal 'file:///test.rb', captured_args[:uri]
      assert captured_args.key?(:diagnostics)
    end
  end

  describe '#on_textDocument_completion' do
    let(:completion_test_file) do
      <<~CODE_FILE
        class CompletionTest
          def method_one
            @instance_var = 1
          end

          def method_two
            met
          end
        end
      CODE_FILE
    end

    before do
      params = {
        'rootPath' => '/test/project',
        'rootUri' => 'file:///test/project'
      }
      server.on_initialize(params)

      project_manager = server.instance_variable_get(:@project_manager)
      project_manager.update_document_content('file:///test.rb', completion_test_file)
    end

    it 'returns completions at position' do
      params = {
        'textDocument' => { 'uri' => 'file:///test.rb' },
        'position' => { 'line' => 6, 'character' => 7 }
      }

      result = server.on_textDocument_completion(params)

      refute_nil(result)
      assert_instance_of Hash, result
      assert result.key?(:items)
      assert_instance_of Array, result[:items]

      # Should find completions starting with "met"
      method_completions = result[:items].select { |item| item[:label].start_with?('met') }
      refute_empty method_completions

      # Should include method_one and method_two
      labels = method_completions.map { |item| item[:label] }
      assert_includes labels, 'method_one'
      assert_includes labels, 'method_two'
    end
  end

  describe '#on_shutdown' do
    it 'returns nil and records the shutdown' do
      refute server.shutdown_requested?
      assert_nil server.on_shutdown({})
      assert server.shutdown_requested?
    end
  end

  describe '#on_exit' do
    it 'exits 0 after shutdown' do
      server.on_shutdown({})
      error = assert_raises(SystemExit) { server.on_exit(nil) }
      assert_equal 0, error.status
    end

    it 'exits 1 without shutdown' do
      error = assert_raises(SystemExit) { server.on_exit(nil) }
      assert_equal 1, error.status
    end
  end

  describe 'Position struct' do
    it 'creates position with line and character' do
      position = RubyLanguageServer::Server::Position.new(10, 5)

      assert_equal 10, position.line
      assert_equal 5, position.character
    end
  end

  describe '#io accessor' do
    it 'allows setting and getting io' do
      test_io = Object.new
      server.io = test_io

      assert_equal test_io, server.io
    end
  end

  describe 'private methods' do
    describe '#uri_from_params' do
      it 'extracts uri from params' do
        params = {
          'textDocument' => { 'uri' => 'file:///test.rb' }
        }

        uri = server.send(:uri_from_params, params)
        assert_equal 'file:///test.rb', uri
      end
    end

    describe '#postition_from_params' do
      it 'creates Position struct from params' do
        params = {
          'position' => { 'line' => 15, 'character' => 20 }
        }

        position = server.send(:postition_from_params, params)

        assert_instance_of RubyLanguageServer::Server::Position, position
        assert_equal 15, position.line
        assert_equal 20, position.character
      end

      it 'converts string values to integers' do
        params = {
          'position' => { 'line' => '25', 'character' => '30' }
        }

        position = server.send(:postition_from_params, params)

        assert_equal 25, position.line
        assert_equal 30, position.character
      end
    end
  end

  describe '#send_diagnostics' do
    before do
      params = {
        'rootPath' => '/test/project',
        'rootUri' => 'file:///test/project'
      }
      server.on_initialize(params)
    end

    it 'updates document content and sends notification' do
      uri = 'file:///test.rb'
      text = 'class Test\nend'

      # Create a simple test double for IO
      captured_method = nil
      captured_args = nil
      test_io = Object.new
      test_io.define_singleton_method(:send_notification) do |method, args|
        captured_method = method
        captured_args = args
      end
      server.io = test_io

      server.send_diagnostics(uri, text)

      assert_equal 'textDocument/publishDiagnostics', captured_method
      assert_equal uri, captured_args[:uri]
      assert captured_args.key?(:diagnostics)
    end
  end
end
