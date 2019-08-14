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

      def root_uri=(uri)
        ROOT_PATH_MUTEX.synchronize do
          if uri
            uri = "#{uri}/" unless uri.end_with?('/')
            @_root_uri = uri
          end
        end
      end

      def root_uri
        @_root_uri || "file://#{root_path}"
      end
    end

    def initialize(path, uri = nil)
      # Should probably lock for read, but I'm feeling crazy!
      self.class.root_path = path if self.class.root_path.nil?
      self.class.root_uri = uri if uri

      @root_uri = "file://#{path}"
      # This is {uri: code_file} where content stuff is like
      @update_mutext = Mutex.new

      @additional_gems_installed = false
      @additional_gem_mutex = Mutex.new
    end

    def diagnostics_ready?
      @additional_gem_mutex.synchronize { @additional_gems_installed }
    end

    def install_additional_gems(gem_names)
      Thread.new do
        RubyLanguageServer::GemInstaller.install_gems(gem_names)
        @additional_gem_mutex.synchronize { @additional_gems_installed = true }
      rescue StandardError => e
        RubyLanguageServer.logger.error("Issue installing rubocop gems: #{e}")
      end
    end

    def text_for_uri(uri)
      code_file = code_file_for_uri(uri)
      code_file&.text || ''
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
      RubyLanguageServer::ScopeData::Scope.all
    end

    # Return the list of scopes [deepest, parent, ..., Object]
    def scopes_at(uri, position)
      code_file = code_file_for_uri(uri)
      code_file.refresh_scopes_if_needed
      code_file.scopes.for_line(position.line).select(&:path).sort_by { |scope| -(scope.path&.length) || 0 }
    end

    def completion_at(uri, position)
      relative_position = position.dup
      relative_position.character = relative_position.character # To get before the . or ::
      # RubyLanguageServer.logger.debug("relative_position #{relative_position}")
      RubyLanguageServer.logger.debug("scopes_at(uri, position) #{scopes_at(uri, position).map(&:name)}")
      position_scopes = scopes_at(uri, position) || RubyLanguageServer::ScopeData::Scope.where(id: root_scope_for(uri).id)
      context_scope = position_scopes.first
      context = context_at_location(uri, relative_position)
      return {} if context.nil? || context == ''

      RubyLanguageServer::Completion.completion(context, context_scope, position_scopes)
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
        RubyLanguageServer.logger.error('Threading up!')
        project_ruby_files.each do |container_path|
          # Let's not preload spec/test or vendor - yet..
          next if container_path.match?(/^(.?spec|test|vendor)/)

          text = File.read(container_path)
          relative_path = container_path.delete_prefix(self.class.root_path)
          host_uri = @root_uri + relative_path
          # ActiveRecord::Base.connection_pool.connection do
          RubyLanguageServer.logger.error("Threading #{host_uri}")
          update_document_content(host_uri, text)
          code_file_for_uri(host_uri).refresh_scopes_if_needed
          # end
        end
      end
    end

    # returns diagnostic info (if possible)
    def update_document_content(uri, text)
      @update_mutext.synchronize do
        RubyLanguageServer.logger.debug("update_document_content: #{uri}")
        # RubyLanguageServer.logger.error("@root_path: #{@root_path}")
        code_file = code_file_for_uri(uri)
        return code_file.diagnostics if code_file.text == text

        code_file.update_text(text)
        diagnostics_ready? ? updated_diagnostics_for_codefile(code_file) : []
      end
    end

    def updated_diagnostics_for_codefile(code_file)
      # Maybe we should be sharing this GoodCop across instances
      @good_cop ||= GoodCop.new
      project_relative_filename = filename_relative_to_project(code_file.uri)
      code_file.diagnostics = @good_cop.diagnostics(code_file.text, project_relative_filename)
    end

    # Returns the context of what is being typed in the given line
    def context_at_location(uri, position)
      code_file = code_file_for_uri(uri)
      code_file&.context_at_location(position)
    end

    def word_at_location(uri, position)
      context_at_location(uri, position)&.last
    end

    def possible_definitions(uri, position)
      name = word_at_location(uri, position)
      return {} if name.blank?

      name = 'initialize' if name == 'new'
      scope = scopes_at(uri, position).first
      results = scope_definitions_for(name, scope, uri)
      return results unless results.empty?

      project_definitions_for(name)
    end

    def scope_definitions_for(name, scope, uri)
      check_scope = scope
      return_array = []
      while check_scope
        scope.variables.each do |variable|
          return_array << Location.hash(uri, variable.line - 1) if variable.name == name
        end
        check_scope = check_scope.parent
      end
      RubyLanguageServer.logger.debug("scope_definitions_for(#{name}, #{scope}, #{uri}: #{return_array.uniq})")
      return_array.uniq
    end

    def project_definitions_for(name)
      scopes = RubyLanguageServer::ScopeData::Scope.where(name: name)
      variables = RubyLanguageServer::ScopeData::Variable.constant_variables.where(name: name)
      (scopes + variables).map do |thing|
        Location.hash(thing.code_file.uri, thing.top_line + 1)
      end
    end

    private

    def code_file_for_uri(uri)
      code_file = CodeFile.find_by_uri(uri) || CodeFile.build(uri, nil)
      code_file
    end

    def filename_relative_to_project(filename)
      filename.gsub(self.class.root_uri, self.class.root_path)
    end
  end
end
