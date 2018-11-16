# frozen_string_literal: true

require 'ripper-tags'
require 'fuzzy_match'
require 'amatch' # note that you have to require this... fuzzy_match won't require it for you
FuzzyMatch.engine = :amatch # This should be in a config somewhere

module RubyLanguageServer
  class ProjectManager
    attr_reader :uri_code_file_hash

    def initialize(uri)
      @root_path = uri
      @root_uri = "file://#{@root_path}"
      # This is {uri: code_file} where content stuff is like
      @uri_code_file_hash = {}
      @update_mutext = Mutex.new
      scan_all_project_files
    end

    def text_for_uri(uri)
      code_file = code_file_for_uri(uri)
      code_file&.text || ''
    end

    def code_file_for_uri(uri, text = nil)
      code_file = @uri_code_file_hash[uri]
      code_file = @uri_code_file_hash[uri] = CodeFile.new(uri, text) if code_file.nil?
      code_file
    end

    def tags_for_uri(uri)
      code_file = code_file_for_uri(uri)
      return {} if code_file.nil?

      code_file.tags
    end

    def root_scope_for(uri)
      code_file = code_file_for_uri(uri)
      RubyLanguageServer.logger.error('code_file.nil?!!!!!!!!!!!!!!') if code_file.nil?
      return code_file.root_scope unless code_file.nil?
    end

    def all_scopes
      @uri_code_file_hash.values.map(&:root_scope).map(&:self_and_descendants).flatten
    end

    # Return the list of scopes [deepest, parent, ..., Object]
    def scopes_at(uri, position)
      root_scope = root_scope_for(uri)
      root_scope.scopes_at(position)
    end

    def completion_at(uri, position)
      relative_position = position.dup
      relative_position.character = relative_position.character # To get before the . or ::
      # RubyLanguageServer.logger.debug("relative_position #{relative_position}")
      RubyLanguageServer.logger.error("scopes_at(uri, position) #{scopes_at(uri, position).map(&:name)}")
      context_scope = scopes_at(uri, position).first || root_scope_for(uri)
      context = context_at_location(uri, relative_position)
      return {} if context.nil? || context == ''

      RubyLanguageServer::Completion.completion(context, context_scope, all_scopes)
    end

    # interface CompletionItem {
    #   /**
    #    * The label of this completion item. By default
    #    * also the text that is inserted when selecting
    #    * this completion.
    #    */
    #   label: string;
    #   /**
    #    * The kind of this completion item. Based of the kind
    #    * an icon is chosen by the editor.
    #    */
    #   kind?: number;
    #   /**
    #    * A human-readable string with additional information
    #    * about this item, like type or symbol information.
    #    */
    #   detail?: string;
    #   /**
    #    * A human-readable string that represents a doc-comment.
    #    */
    #   documentation?: string;
    #   /**
    #    * A string that shoud be used when comparing this item
    #    * with other items. When `falsy` the label is used.
    #    */
    #   sortText?: string;
    #   /**
    #    * A string that should be used when filtering a set of
    #    * completion items. When `falsy` the label is used.
    #    */
    #   filterText?: string;
    #   /**
    #    * A string that should be inserted a document when selecting
    #    * this completion. When `falsy` the label is used.
    #    */
    #   insertText?: string;
    #   /**
    #    * The format of the insert text. The format applies to both the `insertText` property
    #    * and the `newText` property of a provided `textEdit`.
    #    */
    #   insertTextFormat?: InsertTextFormat;
    #   /**
    #    * An edit which is applied to a document when selecting this completion. When an edit is provided the value of
    #    * `insertText` is ignored.
    #    *
    #    * *Note:* The range of the edit must be a single line range and it must contain the position at which completion
    #    * has been requested.
    #    */
    #   textEdit?: TextEdit;
    #   /**
    #    * An optional array of additional text edits that are applied when
    #    * selecting this completion. Edits must not overlap with the main edit
    #    * nor with themselves.
    #    */
    #   additionalTextEdits?: TextEdit[];
    #   /**
    #    * An optional set of characters that when pressed while this completion is active will accept it first and
    #    * then type that character. *Note* that all commit characters should have `length=1` and that superfluous
    #    * characters will be ignored.
    #    */
    #   commitCharacters?: string[];
    #   /**
    #    * An optional command that is executed *after* inserting this completion. *Note* that
    #    * additional modifications to the current document should be described with the
    #    * additionalTextEdits-property.
    #    */
    #   command?: Command;
    #   /**
    #    * An data entry field that is preserved on a completion item between
    #    * a completion and a completion resolve request.
    #    */
    #   data?: any
    # }

    def scan_all_project_files
      project_ruby_files = Dir.glob('/project/**/*.rb')
      RubyLanguageServer.logger.debug("scan_all_project_files: #{project_ruby_files * ','}")
      Thread.new do
        project_ruby_files.each do |container_path|
          text = File.read(container_path)
          relative_path = container_path.delete_prefix('/project/')
          host_uri = @root_uri + relative_path
          update_document_content(host_uri, text)
        end
      end
    end

    def update_document_content(uri, text)
      @update_mutext.synchronize do
        RubyLanguageServer.logger.debug("update_document_content: #{uri}")
        # RubyLanguageServer.logger.error("@root_path: #{@root_path}")
        code_file = code_file_for_uri(uri, text)
        code_file.text = text
        code_file.diagnostics
      end
    end

    def context_at_location(uri, position)
      lines = text_for_uri(uri).split("\n")
      line = lines[position.line]
      RubyLanguageServer.logger.error("LineContext.for(line, position.character): #{LineContext.for(line, position.character)}")
      LineContext.for(line, position.character)
    end

    def word_at_location(uri, position)
      context_at_location(uri, position).last
    end

    def possible_definitions_for(name, scope, uri)
      return {} if name == ''

      name = 'initialize' if name == 'new'
      results = scope_definitions_for(name, scope, uri)
      return results unless results.empty?

      project_definitions_for(name, scope)
    end

    def scope_definitions_for(name, scope, uri)
      check_scope = scope
      return_array = []
      while check_scope
        scope.variables.each do |variable|
          return_array << Location.hash(uri, variable.line) if variable.name == name
        end
        check_scope = check_scope.parent
      end
      return_array.uniq
    end

    def project_definitions_for(name, _scope)
      return_array = @uri_code_file_hash.keys.each_with_object([]) do |uri, ary|
        tags = tags_for_uri(uri)
        RubyLanguageServer.logger.debug("tags_for_uri(#{uri}): #{tags_for_uri(uri)}")
        next if tags.nil?

        match_tags = tags.select { |tag| tag[:name] == name }
        match_tags.each do |tag|
          ary << Location.hash(uri, tag[:location][:range][:start][:line] + 1)
        end
      end
      return_array
    end
  end
end
