# frozen_string_literal: true

require 'fuzzy_match'
require 'amatch' # note that you have to require this... fuzzy_match won't require it for you
FuzzyMatch.engine = :amatch # This should be in a config somewhere

module RubyLanguageServer
  class ProjectManager
    attr_reader :uri_code_file_hash

    # GoodCop wants to know where to find its config.  So here we are.
    ROOT_PATH_MUTEX = Mutex.new
    @_root_path = nil

    class << self
      def root_path=(path)
        ROOT_PATH_MUTEX.synchronize do
          @_root_path = path
        end
      end

      def root_path
        # I'm torn about  this.  Should this be set in the Server?  Or is this right.
        # Rather than worry too much, I'll just do this here and change it later if it feels wrong.
        path = ENV['RUBY_LANGUAGE_SERVER_PROJECT_ROOT'] || @_root_path
        return path if path.nil?

        path.end_with?(File::SEPARATOR) ? path : "#{path}#{File::SEPARATOR}"
      end
    end

    def initialize(path)
      # Should probably lock for read, but I'm feeling crazy!
      self.class.root_path = path if self.class.root_path.nil?
      @root_uri = "file://#{path}"
      # This is {uri: code_file} where content stuff is like
      @uri_code_file_hash = {}
      @update_mutext = Mutex.new

      @additional_gems_installed = false
      @additional_gem_mutex = Mutex.new

      scan_all_project_files
    end

    def diagnostics_ready?
      @additional_gem_mutex.synchronize { @additional_gems_installed }
    end

    def install_additional_gems(gem_names)
      Thread.new do
        RubyLanguageServer::GemInstaller.install_gems(gem_names)
        @additional_gem_mutex.synchronize { @additional_gems_installed = true }
      end
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
      code_file&.root_scope
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
      RubyLanguageServer.logger.debug("scopes_at(uri, position) #{scopes_at(uri, position).map(&:name)}")
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
      project_ruby_files = Dir.glob("#{self.class.root_path}**/*.rb")
      Thread.new do
        project_ruby_files.each do |container_path|
          text = File.read(container_path)
          relative_path = container_path.delete_prefix(self.class.root_path)
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
        diagnostics_ready? ? code_file.diagnostics : []
      end
    end

    # Returns the context of what is being typed in the given line
    def context_at_location(uri, position)
      code_file = code_file_for_uri(uri)
      code_file&.context_at_location(position)
    end

    def word_at_location(uri, position)
      context_at_location(uri, position).last
    end

    def possible_definitions(uri, position)
      name = word_at_location(uri, position)
      return {} if name == ''

      name = 'initialize' if name == 'new'
      scope = scopes_at(uri, position).first
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
      RubyLanguageServer.logger.debug("scope_definitions_for(#{name}, #{scope}, #{uri}: #{return_array.uniq})")
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
