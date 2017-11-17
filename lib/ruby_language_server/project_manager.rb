require 'ripper-tags'
require 'fuzzy_match'
require 'amatch' # note that you have to require this... fuzzy_match won't require it for you
FuzzyMatch.engine = :amatch # This should be in a config somewhere

module RubyLanguageServer

  class ProjectManager

    def initialize(uri)
      # We don't seem to use this - but I'm emotionally attached.
      # Probably will need it when we start parsing/using Gemfile
      @root_path = uri
      # This is {uri: {content stuff}} where content stuff is like text: , tags: ...
      @file_tags = {}
    end

    def text_for_uri(uri)
      hash = @file_tags[uri]
      hash[:text] || ''
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

    # OK - this really does not belong here.  It should probably be in CodeFile.
    def tags_for_text(text, uri)
      cop_tags = RipperTags::Parser.extract(text)

      # Don't freak out and nuke the outline just because we're in the middle of typing a line and you can't parse the file.
      return if (cop_tags.nil? || cop_tags == [])

      tags = cop_tags.map{ |reference|
        return_hash = {
          name: reference[:name] || 'undefined?',
          kind: SymbolKind[reference[:kind].to_sym] || 7,
          location: Location.hash(uri, reference[:line])
        }
        container_name = reference[:full_name].split(/(:{2}|\#|\.)/).compact[-3]
        return_hash[:containerName] = container_name if container_name
        return_hash
      }
      tags.reverse.each do |tag|
        child_tags = tags.select{ |child_tag| child_tag[:containerName] == tag[:name]}
        max_line = child_tags.map{ |child_tag| child_tag[:location][:range][:end][:line].to_i }.max || 0
        tag[:location][:range][:end][:line] = [tag[:location][:range][:end][:line], max_line].max
      end
    end

    def update_tags(uri)
      @file_tags[uri][:tags] = tags_for_text(text_for_uri(uri), uri)
    end

    def tags_for_uri(uri)
      hash = @file_tags[uri][:tags] || {}
    end

    def root_scope_for(uri)
      code_file = @file_tags[uri][:code_file]
      return code_file.root_scope unless code_file.nil?
    end

    def scopes_at(uri, position)
      line = position.line
      root_scope = root_scope_for(uri)
      matching_scopes = root_scope.select{ |scope| scope.top_line && scope.bottom_line && (scope.top_line..scope.bottom_line).include?(line) }
      return [] if matching_scopes == []
      deepest_scope = matching_scopes.sort_by(&:depth).last
      applicable_scopes = deepest_scope.self_and_ancestors
    end

    def scope_completions(word, scopes)
      words = {}
      scopes.inject(words) do |hash, scope|
        scope.children.each{ |function| hash[function.name] ||= {
          depth: scope.depth,
          type: function.type,
          }
        }
        scope.variables.each{ |variable| hash[variable.name] ||= {
          depth: scope.depth,
          type: variable.type,
          }
        }
        hash
      end
      # words = words.sort_by{|word, hash| hash[:depth] }.to_h
      good_words = FuzzyMatch.new(words.keys, threshold: 0.01).find_all(word).slice(0..10) || []
      words = good_words.map{|word| [word, words[word]]}.to_h
    end

    def completion_at(uri, position)
      word = word_at_location(uri, position)
      return {} if word.nil? || word == ''
      applicable_scopes = scopes_at(uri, position)
      RubyLanguageServer.logger.debug("applicable_scopes #{applicable_scopes.map(&:name)}")
      good_words = scope_completions(word, applicable_scopes)
      RubyLanguageServer.logger.debug("good_words #{good_words}")
      {
        isIncomplete: true,
        items: good_words.map do |word, hash|
          {
            label: word,
            kind: CompletionItemKind[hash[:type]],
          }
        end
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


    def update_document_content(uri, text)
      @file_tags[uri] = {text: text}
      @file_tags[uri][:code_file] ||= CodeFile.new(text)
      update_tags(uri)
    end


    def word_at_location(uri, position)
      character = position.character
      lines = text_for_uri(uri).split("\n")
      # Grab the line
      line = lines[position.line]
      return nil if line.nil?
      # Grab just the last part of the line - from the index onward
      line_end = line[character..-1]
      return nil if line_end.nil?
      RubyLanguageServer.logger.debug("line_end: #{line_end}")
      # Grab the portion of the word that starts at the position toward the end of the line
      match = line_end.partition(/^(@{0,2}\w+)/)[1]
      RubyLanguageServer.logger.debug("match: #{match}")
      # Get the start of the line to the end of the matched word
      line_start = line[0..(character + match.length - 1)]
      RubyLanguageServer.logger.debug("line_start: #{line_start}")
      # Match as much as we can to the end of the line - which is now the end of the word
      end_match = line_start.partition(/(@{0,2}\w+)$/)[1]
      RubyLanguageServer.logger.debug("end_match: #{end_match}")
      end_match
    end

    def possible_definitions_for(name)
      return {} if name == ''
      return_array = @file_tags.keys.inject([]) do |return_array, uri|
        tags = tags_for_uri(uri)
        match_tags = tags.select{|tag| tag[:name] == name}
        match_tags.each do |tag|
          return_array << Location.hash(uri, tag[:location][:range][:start][:line] + 1)
        end
        return_array
      end
      return_array
    end

  end
end
