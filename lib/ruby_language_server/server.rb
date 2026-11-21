# frozen_string_literal: true

require 'json'
require 'uri'

# Deal with the various languageserver calls.
module RubyLanguageServer
  class Server
    Position = Struct.new('Position', :line, :character)
    attr_accessor :io

    def on_initialize(params)
      RubyLanguageServer.logger.info("on_initialize: #{params}")
      RubyLanguageServer::CodeFile.all # Just to warm up active_record.
      # rootPath and rootUri are deprecated in favor of workspaceFolders. Only the first
      # folder is indexed.
      root_uri = params['rootUri'] || params.dig('workspaceFolders', 0, 'uri')
      root_path = params['rootPath'] || path_from_file_uri(root_uri)
      @project_manager = ProjectManager.new(root_path, root_uri)
      @project_manager.scan_all_project_files
      @client_capabilities = params['capabilities'] || {}
      {
        # Advertise only capabilities that have an on_* handler. Requests for anything
        # else get a MethodNotFound error (see IO#process_request).
        capabilities: {
          textDocumentSync: 1,
          definitionProvider: true,
          documentSymbolProvider: true,
          hoverProvider: true,
          completionProvider: {
            triggerCharacters: ['.', '::']
          }
        },
        serverInfo: {
          name: 'ruby_language_server',
          version: RubyLanguageServer::VERSION
        }
      }
    end

    def on_initialized(_hash)
      RubyLanguageServer.logger.info("RubyLanguageServer::VERSION #{RubyLanguageServer::VERSION}")
      register_file_watcher
    end

    # Ask the client to tell us when Ruby files are created, changed or deleted, so the
    # index doesn't keep files that are gone. Only clients that support dynamic
    # registration for workspace/didChangeWatchedFiles are asked.
    def register_file_watcher
      return unless @client_capabilities&.dig('workspace', 'didChangeWatchedFiles', 'dynamicRegistration')

      io.send_request('client/registerCapability', registrations: [{
                        id: 'ruby_language_server-watched-files',
                        method: 'workspace/didChangeWatchedFiles',
                        registerOptions: { watchers: [{ globPattern: '**/*.rb' }] }
                      }])
    end

    def on_workspace_didChangeWatchedFiles(params)
      RubyLanguageServer.logger.debug("on_workspace_didChangeWatchedFiles #{params}")
      @project_manager.watched_files_changed(params['changes'] || [])
      nil # A notification: there is no reply.
    end

    def on_textDocument_hover(params)
      RubyLanguageServer.logger.debug("on_textDocument_hover #{params}")
      @project_manager.hover_at(uri_from_params(params), postition_from_params(params))
    end

    def on_textDocument_documentSymbol(params)
      RubyLanguageServer.logger.debug('on_textDocument_documentSymbol')
      RubyLanguageServer.logger.debug(params)
      uri = uri_from_params(params)

      # {"kind":"module","line":4,"language":"Ruby","path":"(eval)","pattern":"module RubyLanguageServer","full_name":"RubyLanguageServer","name":"RubyLanguageServer"}
      symbols = @project_manager.tags_for_uri(uri)
      RubyLanguageServer.logger.debug("symbols #{symbols}")
      symbols
    end

    def on_textDocument_definition(params)
      RubyLanguageServer.logger.debug("on_textDocument_definition #{params}")
      uri = uri_from_params(params)
      position = postition_from_params(params)
      @project_manager.possible_definitions(uri, position)
    end

    # The server has no diagnostics of its own (RuboCop was removed in 0.4.0), so this
    # always publishes an empty list. LSP requires an array here, never null.
    def send_diagnostics(uri, text)
      @project_manager.update_document_content(uri, text)
      io.send_notification('textDocument/publishDiagnostics', uri:, diagnostics: [])
    end

    def on_textDocument_didOpen(params)
      textDocument = params['textDocument']
      uri = textDocument['uri']
      RubyLanguageServer.logger.debug("on_textDocument_didOpen #{uri}")
      text = textDocument['text']
      send_diagnostics(uri, text)
    end

    def on_textDocument_didChange(params)
      uri = uri_from_params(params)
      RubyLanguageServer.logger.debug("on_textDocument_didChange #{uri}")
      content_changes = params['contentChanges']
      text = content_changes.first['text']
      send_diagnostics(uri, text)
    end

    def on_textDocument_completion(params)
      RubyLanguageServer.logger.info("on_textDocument_completion #{params}")
      uri = uri_from_params(params)
      position = postition_from_params(params)
      completions = @project_manager.completion_at(uri, position)
      RubyLanguageServer.logger.debug("completions: #{completions}")
      completions
    end

    # LSP shutdown request: stop serving, but don't exit until the exit notification.
    def on_shutdown(_params)
      RubyLanguageServer.logger.info('on_shutdown')
      @shutdown_requested = true
      nil
    end

    # LSP exit notification: exit 0 if shutdown came first, 1 otherwise.
    def on_exit(_params)
      RubyLanguageServer.logger.info("on_exit (shutdown requested: #{shutdown_requested?})")
      exit(shutdown_requested? ? 0 : 1)
    end

    def shutdown_requested?
      @shutdown_requested == true
    end

    private

    def path_from_file_uri(uri)
      return nil unless uri&.start_with?('file://')

      URI.decode_uri_component(URI(uri).path)
    end

    def uri_from_params(params)
      textDocument = params['textDocument']
      textDocument['uri']
    end

    def postition_from_params(params)
      position = params['position']
      Position.new(position['line'].to_i, position['character'].to_i)
    end
  end
end
