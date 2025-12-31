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
      assert_equal 1, capabilities[:textDocumentSync]
      assert_equal true, capabilities[:hoverProvider]
      assert_equal true, capabilities[:definitionProvider]
      assert_equal true, capabilities[:referencesProvider]
      assert_equal true, capabilities[:documentSymbolProvider]
      assert_equal true, capabilities[:workspaceSymbolProvider]
      assert_equal true, capabilities[:codeActionProvider]
      assert_equal true, capabilities[:renameProvider]
    end

    it 'sets up signature help provider' do
      result = server.on_initialize(params)

      signature_help = result[:capabilities][:signatureHelpProvider]
      refute_nil(signature_help)
      assert_equal ['(', ','], signature_help[:triggerCharacters]
    end

    it 'sets up completion provider' do
      result = server.on_initialize(params)

      completion = result[:capabilities][:completionProvider]
      refute_nil(completion)
      assert_equal true, completion[:resolveProvider]
      assert_equal ['.', '::'], completion[:triggerCharacters]
    end

    it 'sets up execute command provider' do
      result = server.on_initialize(params)

      execute_command = result[:capabilities][:executeCommandProvider]
      refute_nil(execute_command)
      assert_equal [], execute_command[:commands]
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
    it 'returns empty hash' do
      params = { 'changes' => [] }
      result = server.on_workspace_didChangeWatchedFiles(params)

      assert_equal({}, result)
    end
  end

  describe '#on_textDocument_hover' do
    it 'returns empty hash' do
      params = {
        'textDocument' => { 'uri' => 'file:///test.rb' },
        'position' => { 'line' => 0, 'character' => 0 }
      }
      result = server.on_textDocument_hover(params)

      assert_equal({}, result)
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
    before do
      params = {
        'rootPath' => '/test/project',
        'rootUri' => 'file:///test/project'
      }
      server.on_initialize(params)
    end

    it 'returns completions at position' do
      params = {
        'textDocument' => { 'uri' => 'file:///test.rb' },
        'position' => { 'line' => 3, 'character' => 5 }
      }

      project_manager = server.instance_variable_get(:@project_manager)
      def project_manager.completion_at(_uri, _position)
        [{ label: 'method_name', kind: 2 }]
      end

      result = server.on_textDocument_completion(params)

      refute_nil(result)
      assert_equal [{ label: 'method_name', kind: 2 }], result
    end
  end

  describe '#on_shutdown' do
    it 'logs shutdown' do
      server.on_shutdown({})
      # Just verify it doesn't raise an error
      assert true
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
