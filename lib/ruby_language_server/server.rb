require 'json'

module RubyLanguageServer
  class Server
    def on_initialize(params)
      @root_path = params['rootPath']
      {
        capabilities: {
          # textDocumentSync: TextDocumentSyncKind.Full,
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
  end
end
