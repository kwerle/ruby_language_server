require 'json'

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
      RubyLanguageServer.logger.debug('==============================================')
      RubyLanguageServer.logger.debug(params)
      {}
    end

    def on_textDocument_hover(params)
      RubyLanguageServer.logger.debug('----------------------------------------------')
      RubyLanguageServer.logger.debug(params)
      {}
    end

    def on_textDocument_documentSymbol(params)
      RubyLanguageServer.logger.debug('??????????????????????????????????????????????')
      RubyLanguageServer.logger.debug(params)
      uri = uri_from_params(params)

      # {"kind":"module","line":4,"language":"Ruby","path":"(eval)","pattern":"module RubyLanguageServer","full_name":"RubyLanguageServer","name":"RubyLanguageServer"}
      @project_manager.tags_for_uri(uri)
    end

    def on_textDocument_definition(params)
      RubyLanguageServer.logger.debug('??????????????????????????????????????????????')
      RubyLanguageServer.logger.debug(params)
      uri = uri_from_params(params)
      position = params['position']
      line_number = (position['line']).to_i
      RubyLanguageServer.logger.debug("line number: #{line_number}")
      character = position['character'].to_i
      lines = @project_manager.text_for_uri(uri).split("\n")
      line = lines[line_number]
      return nil if line.nil?
      line_end = line[character..-1]
      return nil if line_end.nil?
      RubyLanguageServer.logger.debug("line_end: #{line_end}")
      match = line_end.partition(/^(@{0,2}\w+)/)[1]
      RubyLanguageServer.logger.debug("match: #{match}")
      line_start = line[0..(character + match.length - 1)]
      RubyLanguageServer.logger.debug("line_start: #{line_start}")
      end_match = line_start.partition(/(@{0,2}\w+)$/)[1]
      RubyLanguageServer.logger.debug("end_match: #{end_match}")
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

    private

    def uri_from_params(params)
      textDocument = params['textDocument']
      uri = textDocument['uri']
    end

  end

end
