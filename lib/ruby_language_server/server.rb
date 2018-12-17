# frozen_string_literal: true

require 'json'

# Deal with the various languageserver calls.
module RubyLanguageServer
  class Server
    attr_accessor :io

    def on_initialize(params)
      RubyLanguageServer.logger.error("on_initialize: #{params}")
      root_path = params['rootPath']
      @project_manager = ProjectManager.new(root_path)
      # gem_string = ENV.fetch('ADDITIONAL_GEMS') { 'rubocop-rails_config' }
      gem_array = gem_string.split(',').compact.map(&:strip).reject { |string| string == '' }
      @project_manager.install_additional_gems(gem_array)
      # @file_tags = {}
      {
        capabilities: {
          textDocumentSync: 1,
          hoverProvider: true,
          signatureHelpProvider: {
            triggerCharacters: ['(', ',']
          },
          definitionProvider: true,
          referencesProvider: true,
          documentSymbolProvider: true,
          workspaceSymbolProvider: true,
          xworkspaceReferencesProvider: true,
          xdefinitionProvider: true,
          xdependenciesProvider: true,
          completionProvider: {
            resolveProvider: true,
            triggerCharacters: ['.', '::']
          },
          codeActionProvider: true,
          renameProvider: true,
          executeCommandProvider: {
            commands: []
          },
          xpackagesProvider: true
        }
      }
    end

    def on_workspace_didChangeWatchedFiles(params)
      RubyLanguageServer.logger.debug('on_workspace_didChangeWatchedFiles')
      RubyLanguageServer.logger.debug(params)
      {}
    end

    def on_textDocument_hover(params)
      RubyLanguageServer.logger.debug('on_textDocument_hover')
      RubyLanguageServer.logger.debug(params)
      {}
    end

    def on_textDocument_documentSymbol(params)
      RubyLanguageServer.logger.debug('on_textDocument_documentSymbol')
      RubyLanguageServer.logger.debug(params)
      uri = uri_from_params(params)

      # {"kind":"module","line":4,"language":"Ruby","path":"(eval)","pattern":"module RubyLanguageServer","full_name":"RubyLanguageServer","name":"RubyLanguageServer"}
      @project_manager.tags_for_uri(uri)
    end

    def on_textDocument_definition(params)
      RubyLanguageServer.logger.debug('on_textDocument_definition')
      RubyLanguageServer.logger.debug(params)
      uri = uri_from_params(params)
      position = postition_from_params(params)
      @project_manager.possible_definitions(uri, position)
    end

    def send_diagnostics(uri, text)
      hash = @project_manager.update_document_content(uri, text)
      io.send_notification('textDocument/publishDiagnostics', uri: uri, diagnostics: hash)
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
      @project_manager.completion_at(uri, position)
    end

    def on_shutdown(params)
      # "EXIT"
    end

    private

    def uri_from_params(params)
      textDocument = params['textDocument']
      textDocument['uri']
    end

    Position = Struct.new('Position', :line, :character)

    def postition_from_params(params)
      position = params['position']
      Position.new((position['line']).to_i, position['character'].to_i)
    end
  end
end
