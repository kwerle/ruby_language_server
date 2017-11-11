require 'json'

# Deal with the various languageserver calls.
module RubyLanguageServer
  class Server

    def on_initialize(params)
      root_path = params['rootPath']
      @project_manager = ProjectManager.new(root_path)
      @file_tags = {}
      {
        capabilities: {
          textDocumentSync: 1,
          hoverProvider: true,
          signatureHelpProvider: {
            triggerCharacters: ['(', ','],
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
            triggerCharacters: ['.', '::'],
          },
          codeActionProvider: true,
          renameProvider: true,
          executeCommandProvider: {
            commands: [],
          },
          xpackagesProvider: true,
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
      end_match = @project_manager.word_at_location(uri, position)
      @project_manager.possible_definitions_for(end_match)
    end

    def on_textDocument_publishDiagnostics
      @good_cop ||= GoodCop.new()
      cop_out = @good_cop.diagnostics(text)
    end

    def on_textDocument_didOpen(params)
      textDocument = params['textDocument']
      uri = textDocument['uri']
      text = textDocument['text']
      RubyLanguageServer.logger.debug(params.keys)
      RubyLanguageServer.logger.debug("uri: #{uri}")
      RubyLanguageServer.logger.debug("text: #{text}")
      @project_manager.update_document_content(uri, text)
      {}
    end

    def on_textDocument_didChange(params)
      uri = uri_from_params(params)
      contentChanges = params['contentChanges']
      text = contentChanges.first['text']
      RubyLanguageServer.logger.debug(params.keys)
      RubyLanguageServer.logger.debug("uri: #{uri}")
      RubyLanguageServer.logger.debug("contentChanges: #{contentChanges}")
      @project_manager.update_document_content(uri, text)
      {}
    end

    def on_textDocument_completion(params)
      RubyLanguageServer.logger.error(params)
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
      uri = textDocument['uri']
    end

    Position = Struct.new('Position', :line, :character)

    def postition_from_params(params)
      position = params['position']
      Position.new((position['line']).to_i, position['character'].to_i)
    end

  end

end
