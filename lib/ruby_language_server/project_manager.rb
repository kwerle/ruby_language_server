require 'ripper-tags'
require 'fuzzy_match'
require 'amatch' # note that you have to require this... fuzzy_match won't require it for you
FuzzyMatch.engine = :amatch # This should be in a config somewhere

module RubyLanguageServer

  class ProjectManager

    def initialize(uri)
      @root_path = uri
      @root_uri = "file://#{@root_path}"
      # This is {uri: {content stuff}} where content stuff is like text: , tags: ...
      @file_tags = {}
      @update_mutext = Mutex.new
      scan_all_project_files()
    end

    def text_for_uri(uri)
      # hash = @file_tags[uri]
      # hash[:text] || ''
      code_file = code_file_for_uri(uri)
      code_file&.text || ''
    end

    def update_tags(uri, text)
      code_file = code_file_for_uri(uri)
      tags = code_file_for_uri(uri).tags
      @file_tags[uri][:tags] = tags
    end

    def code_file_for_uri(uri, text = nil)
      code_file = @file_tags[uri][:code_file]
      if code_file.nil?
        code_file = @file_tags[uri][:code_file] = CodeFile.new(uri, text)
      end
      code_file
    end

    def tags_for_uri(uri)
      # RubyLanguageServer.logger.debug("tags_for_uri: #{uri}")
      code_file = code_file_for_uri(uri)
      # RubyLanguageServer.logger.debug("tags_for_uri: code_file #{code_file}")
      return {} if code_file.nil?
      # RubyLanguageServer.logger.debug("tags_for_uri code_file.tags: #{code_file.tags}")
      @file_tags[uri][:tags] = code_file.tags
    end

    def root_scope_for(uri)
      code_file = code_file_for_uri(uri)
      RubyLanguageServer.logger.error("code_file.nil?!!!!!!!!!!!!!!") if code_file.nil?
      return code_file.root_scope unless code_file.nil?
    end

    def scopes_at(uri, position)
      root_scope = root_scope_for(uri)
      root_scope.scopes_at(position)
    end

    # This really wants more refactoring
    def scope_completions(context, scopes)
      word = context.last
      words = {}
      scopes.inject(words) do |words_hash, scope|
        scope.children.each{ |function| words_hash[function.name] ||= {
          depth: scope.depth,
          type: function.type,
          }
        }
        scope.variables.each{ |variable| words_hash[variable.name] ||= {
          depth: scope.depth,
          type: variable.type,
          }
        }
        words_hash
      end
      # words = words.sort_by{|word, hash| hash[:depth] }.to_h
      good_words = FuzzyMatch.new(words.keys, threshold: 0.01).find_all(word).slice(0..10) || []
      words = good_words.map{|w| [w, words[w]]}.to_h
    end

    def completion_at(uri, position)
      relative_position = position.dup
      relative_position.character = relative_position.character - 2 # To get before the . or ::
      # RubyLanguageServer.logger.debug("relative_position #{relative_position}")
      words = context_at_location(uri, relative_position)
      return {} if words.nil? || words == ''
      RubyLanguageServer.logger.debug("words #{words}")
      applicable_scopes = scopes_at(uri, position)
      RubyLanguageServer.logger.debug("applicable_scopes #{applicable_scopes.to_s}")
      good_words = scope_completions(words, applicable_scopes)
      RubyLanguageServer.logger.debug("good_words #{good_words}")
      # [
      #   {
      #   	label: 'string;',
      #   	kind: 'number;',
      #   	# detail: 'string;',
      #   	# documentation: 'string;',
      #   	# sortText: 'string;',
      #   	# filterText: 'string;',
      #   	# insertText: 'string;',
      #   	# insertTextFormat: 'InsertTextFormat;',
      #   	# textEdit: 'TextEdit;',
      #   	# additionalTextEdits: 'TextEdit[];',
      #   	# commitCharacters: 'string[];',
      #   	# command: 'Command;',
      #   	# data: 'any',
      #   }
      # ]
      {
        isIncomplete: true,
        items: good_words.map do |word, hash|
          {
            label: word,
            kind: CompletionItemKind[hash[:type]],
          }
        end
      }
    end

    CompletionItemKind = {
      text: 1,
      method: 2,
      function: 3,
      constructor: 4,
      field: 5,
      variable: 6,
      :class => 7,
      interface: 8,
      :module => 9,
      property: 10,
      unit: 11,
      value: 12,
      enum: 13,
      keyword: 14,
      snippet: 15,
      color: 16,
      file: 17,
      reference: 18,
    }

    # interface CompletionItem {
    # 	/**
    # 	 * The label of this completion item. By default
    # 	 * also the text that is inserted when selecting
    # 	 * this completion.
    # 	 */
    # 	label: string;
    # 	/**
    # 	 * The kind of this completion item. Based of the kind
    # 	 * an icon is chosen by the editor.
    # 	 */
    # 	kind?: number;
    # 	/**
    # 	 * A human-readable string with additional information
    # 	 * about this item, like type or symbol information.
    # 	 */
    # 	detail?: string;
    # 	/**
    # 	 * A human-readable string that represents a doc-comment.
    # 	 */
    # 	documentation?: string;
    # 	/**
    # 	 * A string that shoud be used when comparing this item
    # 	 * with other items. When `falsy` the label is used.
    # 	 */
    # 	sortText?: string;
    # 	/**
    # 	 * A string that should be used when filtering a set of
    # 	 * completion items. When `falsy` the label is used.
    # 	 */
    # 	filterText?: string;
    # 	/**
    # 	 * A string that should be inserted a document when selecting
    # 	 * this completion. When `falsy` the label is used.
    # 	 */
    # 	insertText?: string;
    # 	/**
    # 	 * The format of the insert text. The format applies to both the `insertText` property
    # 	 * and the `newText` property of a provided `textEdit`.
    # 	 */
    # 	insertTextFormat?: InsertTextFormat;
    # 	/**
    # 	 * An edit which is applied to a document when selecting this completion. When an edit is provided the value of
    # 	 * `insertText` is ignored.
    # 	 *
    # 	 * *Note:* The range of the edit must be a single line range and it must contain the position at which completion
    # 	 * has been requested.
    # 	 */
    # 	textEdit?: TextEdit;
    # 	/**
    # 	 * An optional array of additional text edits that are applied when
    # 	 * selecting this completion. Edits must not overlap with the main edit
    # 	 * nor with themselves.
    # 	 */
    # 	additionalTextEdits?: TextEdit[];
    # 	/**
    # 	 * An optional set of characters that when pressed while this completion is active will accept it first and
    # 	 * then type that character. *Note* that all commit characters should have `length=1` and that superfluous
    # 	 * characters will be ignored.
    # 	 */
    # 	commitCharacters?: string[];
    # 	/**
    # 	 * An optional command that is executed *after* inserting this completion. *Note* that
    # 	 * additional modifications to the current document should be described with the
    # 	 * additionalTextEdits-property.
    # 	 */
    # 	command?: Command;
    # 	/**
    # 	 * An data entry field that is preserved on a completion item between
    # 	 * a completion and a completion resolve request.
    # 	 */
    # 	data?: any
    # }

    def scan_all_project_files
      project_ruby_files = Dir.glob("/project/**/*.rb")
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
        @file_tags[uri] ||= {}
        # @file_tags[uri][:text] = text
        # RubyLanguageServer.logger.error("@root_path: #{@root_path}")
        code_file = code_file_for_uri(uri, text)
        code_file.text = text
        update_tags(uri, text)
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

    def possible_definitions_for(name)
      return {} if name == ''
      name = 'initialize' if name == 'new'
      return_array = @file_tags.keys.inject([]) do |ary, uri|
        tags = tags_for_uri(uri)
        RubyLanguageServer.logger.debug("tags_for_uri(#{uri}): #{tags_for_uri(uri)}")
        unless tags.nil?
          match_tags = tags.select{|tag| tag[:name] == name}
          match_tags.each do |tag|
            ary << Location.hash(uri, tag[:location][:range][:start][:line] + 1)
          end
        end
        ary
      end
      return_array
    end

  end
end
