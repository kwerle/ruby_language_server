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
      :'module' => 5, #2,
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
      uri = uri_from_params(params)
      # RubyLanguageServer.logger.error(tags_for_uri(uri))

      # {"kind":"module","line":4,"language":"Ruby","path":"(eval)","pattern":"module RubyLanguageServer","full_name":"RubyLanguageServer","name":"RubyLanguageServer"}
      tags_for_uri(uri).map{ |reference|
        return_hash = {
          name: reference[:name] || 'undefined?',
          kind: SymbolKind[reference[:kind].to_sym] || 7,
          location: location_hash(uri, reference[:line])
        }
        container_name = reference[:full_name].split(/(:{2}|\#)/).compact[-3]
        return_hash[:containerName] = container_name if container_name
        return_hash
      }
    end

    def on_textDocument_definition(params)
      RubyLanguageServer.logger.debug('??????????????????????????????????????????????')
      RubyLanguageServer.logger.debug(params)
      uri = uri_from_params(params)
      position = params['position']
      line_number = (position['line']).to_i
      RubyLanguageServer.logger.debug("line number: #{line_number}")
      character = position['character'].to_i
      lines = text_for_uri(uri).split("\n")
      line = lines[line_number]
      return nil if line.nil?
      line_end = line[character..-1]
      RubyLanguageServer.logger.debug("line_end: #{line_end}")
      match = line_end.partition(/^(@{0,2}\w+)/)[1]
      RubyLanguageServer.logger.debug("match: #{match}")
      line_start = line[0..(character + match.length - 1)]
      RubyLanguageServer.logger.debug("line_start: #{line_start}")
      end_match = line_start.partition(/(@{0,2}\w+)$/)[1]
      RubyLanguageServer.logger.debug("end_match: #{end_match}")
      possible_definitions_for(end_match)
    end

    def on_textDocument_publishDiagnostics
      @good_cop ||= GoodCop.new()
      cop_out = @good_cop.diagnostics(text)
    end

    def possible_definitions_for(name)
      return {} if name == ''
      return_array = @file_tags.keys.inject([]) do |return_array, uri|
        tags = tags_for_uri(uri)
        match_tags = tags.select{|tag| tag[:name] == name}
        match_tags.each do |tag|
          return_array << location_hash(uri, tag[:line])
        end
        return_array
      end
      return_array
    end

    def on_textDocument_didOpen(params)
      textDocument = params['textDocument']
      uri = textDocument['uri']
      text = textDocument['text']
      RubyLanguageServer.logger.debug(params.keys)
      RubyLanguageServer.logger.debug("uri: #{uri}")
      RubyLanguageServer.logger.debug("text: #{text}")
      update_document_content(uri, text)
      {}
    end

    def on_textDocument_didChange(params)
      uri = uri_from_params(params)
      contentChanges = params['contentChanges']
      text = contentChanges.first['text']
      RubyLanguageServer.logger.debug(params.keys)
      RubyLanguageServer.logger.debug("uri: #{uri}")
      RubyLanguageServer.logger.debug("contentChanges: #{contentChanges}")
      update_document_content(uri, text)
      {}
    end

    private

    def text_for_uri(uri)
      hash = @file_tags[uri] || return
      hash[:text]
    end

    def tags_for_uri(uri)
      hash = @file_tags[uri] || return
      hash[:tags]
    end

    def update_document_content(uri, text)
      tags = RipperTags::Parser.extract(text)
      @file_tags[uri] = {
        tags: tags,
        text: text
      }
    end

    def uri_from_params(params)
      textDocument = params['textDocument']
      uri = textDocument['uri']
    end

    def location_hash(uri, start_line, start_character = 1, end_line = nil, end_character = nil)
      _end_line = end_line || start_line
      _end_character = end_character || start_character
      {
        uri: uri,
        range: {
          start: {
            line: start_line - 1,
            character: start_character
          },
          end: {
            line: _end_line - 1,
            character: _end_character
          }
        }
      }
      # Location.hash(uri, start_line, start_character, end_line, end_character)
    end
  end
end
