require 'json'
require 'ripper-tags'

module RubyLanguageServer
  class Server
    attr :root_path
    attr :file_tags

    def on_initialize(params)
      @root_path = params['rootPath']
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
            triggerCharacters: ['.'],
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

    SymbolKind = {
      file: 1,
      module: 2,
      namespace: 3,
      package: 4,
      :'class' => 5,
      :'method' => 6,
      property: 7,
      field: 8,
      constructor: 9,
      enum: 10,
      interface: 11,
      function: 12,
      variable: 13,
      constant: 14,
      string: 15,
      number: 16,
      boolean: 17,
      array: 18,
    }

    def on_textDocument_documentSymbol(params)
      RubyLanguageServer.logger.debug('??????????????????????????????????????????????')
      RubyLanguageServer.logger.debug(params)
      textDocument = params['textDocument']
      uri = textDocument['uri']
      RubyLanguageServer.logger.info(@file_tags[uri])

      # {"kind":"module","line":4,"language":"Ruby","path":"(eval)","pattern":"module RubyLanguageServer","full_name":"RubyLanguageServer","name":"RubyLanguageServer"}
      @file_tags[uri].map{ |reference|
        {
          name: reference[:name] || 'undefined?',
          kind: SymbolKind[reference[:kind].to_sym] || 7,
          # containerName: reference[:full_name],
          location: {
            uri: uri,
            range: {
              start: {
                line: reference[:line] - 1,
                character: 1
              },
              end: {
                line: reference[:line] - 1,
                character: 1
              }
            }
          }
        }
      }
    end

    def on_textDocument_definition(params)
      RubyLanguageServer.logger.debug('??????????????????????????????????????????????')
      RubyLanguageServer.logger.debug(params)
      position = params['position']
      line = position['line']
      character = position['character']
      {}
    end

    def on_textDocument_didOpen(params)
      textDocument = params['textDocument']
      uri = textDocument['uri']
      text = textDocument['text']
      RubyLanguageServer.logger.debug(params.keys)
      RubyLanguageServer.logger.debug("uri: #{uri}")
      RubyLanguageServer.logger.debug("text: #{text}")
      tags = RipperTags::Parser.extract(text)
      update_file_tags(uri, tags)
      RubyLanguageServer.logger.debug(tags)
      {}
    end

    def on_textDocument_didChange(params)
      textDocument = params['textDocument']
      uri = textDocument['uri']
      contentChanges = params['contentChanges']
      text = contentChanges.first['text']
      RubyLanguageServer.logger.debug(params.keys)
      RubyLanguageServer.logger.debug("uri: #{uri}")
      RubyLanguageServer.logger.debug("contentChanges: #{contentChanges}")
      tags = RipperTags::Parser.extract(text)
      update_file_tags(uri, tags)
      RubyLanguageServer.logger.debug(tags)
      {}
    end

    def update_file_tags(uri, tags)
      @file_tags[uri] = tags
    end
  end
end
