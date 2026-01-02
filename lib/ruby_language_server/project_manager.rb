# frozen_string_literal: true

require 'fuzzy_match'
require 'amatch' # NOTE: that you have to require this... fuzzy_match won't require it for you
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
        # I'm torn about this.  Should this be set in the Server?  Or is this right.
        # Rather than worry too much, I'll just do this here and change it later if it feels wrong.
        path = ENV.fetch('RUBY_LANGUAGE_SERVER_PROJECT_ROOT') { @_root_path }
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
      # @additional_gems_installed = false
      # @additional_gem_mutex = Mutex.new
    end

    # def diagnostics_ready?
    #   @additional_gem_mutex.synchronize { @additional_gems_installed }
    # end

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
      code_file.scopes.for_line(position.line).where.not(path: nil).by_path_length
    end

    def completion_at(uri, position)
      context = context_at_location(uri, position)
      return {} if context.blank?

      RubyLanguageServer.logger.debug("scopes_at(uri, position) #{scopes_at(uri, position).map(&:name)}")
      position_scopes = scopes_at(uri, position) || RubyLanguageServer::ScopeData::Scope.where(id: root_scope_for(uri).id)
      context_scope = position_scopes.first
      RubyLanguageServer::Completion.completion(context, context_scope, position_scopes)
    end

    def scan_all_project_files
      project_ruby_files = Dir.glob("#{self.class.root_path}**/*.rb")
      RubyLanguageServer.logger.debug('Threading up!')
      root_uri = @root_uri
      root_uri += '/' unless root_uri.end_with? '/'
      # Using fork because this is run in a docker container that has fork.
      # If you want to run this on some platform without fork, fork the code and PR it :-)
      fork_id = fork do
        project_ruby_files.each do |container_path|
          # Let's not preload spec/test files or vendor - yet..
          next if container_path.match?(/(spec\.rb|test\.rb|vendor)/)

          text = File.read(container_path)
          relative_path = container_path.delete_prefix(self.class.root_path)
          host_uri = root_uri + relative_path
          RubyLanguageServer.logger.debug("Threading #{host_uri}")
          begin
            ActiveRecord::Base.connection_pool.with_connection do |_connection|
              update_document_content(host_uri, text)
              code_file_for_uri(host_uri).refresh_scopes_if_needed(shallow: true)
            end
          rescue StandardError => e
            RubyLanguageServer.logger.warn("Error updating: #{e}\n#{e.backtrace * "\n"}")
            sleep 5
            retry
          end
        end
      end
      RubyLanguageServer.logger.debug("Forked process id to look at other files: #{fork_id}")
      Process.detach(fork_id)
    end

    # returns diagnostic info (if possible)
    def update_document_content(uri, text)
      RubyLanguageServer.logger.debug("update_document_content: #{uri}")
      # RubyLanguageServer.logger.error("@root_path: #{@root_path}")
      code_file = code_file_for_uri(uri)
      return code_file.diagnostics if code_file.text == text

      code_file.update_text(text)
      # diagnostics_ready? ? updated_diagnostics_for_codefile(code_file) : []
    end

    # def updated_diagnostics_for_codefile(code_file)
    #   # Maybe we should be sharing this GoodCop across instances
    #   RubyLanguageServer.logger.debug("updated_diagnostics_for_codefile: #{code_file.uri}")
    #   project_relative_filename = filename_relative_to_project(code_file.uri)
    #   # code_file.diagnostics = GoodCop.instance&.diagnostics(code_file.text, project_relative_filename)
    #   RubyLanguageServer.logger.debug("code_file.diagnostics: #{code_file.diagnostics}")
    #   code_file.diagnostics
    # end

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

      # Special case: "new" should find "initialize" (instance method, not class method)
      name = 'initialize' if name == 'new'

      context = context_at_location(uri, position)

      # If context has more than one element it's a method call on a receiver
      if context.length > 1
        receiver = context.first
        # Determine if it's a class method call (Foo.method) or instance method call (foo.method)
        if likely_class_name?(receiver)
          # Class method call or MyClass.new (which finds initialize as instance method)
          # initialize is weird because it's defined as an instance method but called on the class via new.
          return project_definitions_for(name, name == 'initialize' ? false : true)
        else
          # Instance method call (e.g., foo.bar, @foo.bar, FOO.bar)
          return project_definitions_for(name, false)
        end
      end

      # No receiver - search in scope chain first, then project-wide
      scope = scopes_at(uri, position).first
      results = scope_definitions_for(name, scope, uri)
      return results unless results.empty?

      project_definitions_for(name)
    end

    # Return variables found in the current scope.  After all, those are the important ones.
    # Should probably be private...
    def scope_definitions_for(name, scope, uri)
      check_scope = scope
      return_array = []
      while check_scope
        check_scope.variables.each do |variable|
          return_array << Location.hash(uri, variable.line, 1) if variable.name == name
        end
        check_scope = check_scope.parent
      end
      RubyLanguageServer.logger.debug("==============>> scope_definitions_for(#{name}, #{scope.to_json}, #{uri}: #{return_array.uniq})")
      return_array.uniq
    end

    def project_definitions_for(name, class_method_filter = nil)
      scopes = RubyLanguageServer::ScopeData::Scope.where(name:)

      # Filter by class_method attribute if specified
      unless class_method_filter.nil?
        scopes = scopes.where(class_method: class_method_filter)
      end

      variables = RubyLanguageServer::ScopeData::Variable.constant_variables.where(name:)
      (scopes + variables).reject { |scope| scope.code_file.nil? }.map do |scope|
        Location.hash(scope.code_file.uri, scope.top_line, 1)
      end
    end

    private

    # Guess if a receiver name is likely a class name based on idiomatic Ruby conventions.
    # This is a heuristic and not 100% accurate (e.g., FOO could be a constant holding an instance).
    # Returns true for names like "Foo" or "FooBar" (starts with uppercase, has lowercase letters).
    # Returns false for "FOO" (all uppercase constant) or "foo" (variable/method).
    def likely_class_name?(name)
      # Must start with uppercase letter
      return false unless name[0] =~ /[A-Z]/

      # Must contain at least one lowercase letter to distinguish from constants like FOO
      name =~ /[a-z]/
    end

    def code_file_for_uri(uri)
      CodeFile.find_by_uri(uri) || CodeFile.build(uri, nil)
    end

    def filename_relative_to_project(filename)
      filename.gsub(self.class.root_uri, self.class.root_path)
    end
  end
end
