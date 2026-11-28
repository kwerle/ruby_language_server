# frozen_string_literal: true

require 'uri'
require 'fuzzy_match'
require 'amatch' # NOTE: that you have to require this... fuzzy_match won't require it for you
FuzzyMatch.engine = :amatch # This should be in a config somewhere

module RubyLanguageServer
  class ProjectManager
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

      # Let's not preload spec/test files or vendor - yet.
      # Matches foo_spec.rb, foo_test.rb, spec.rb and test.rb, and anything in a vendor
      # directory, but not files that merely contain those words, like latest.rb.
      SKIP_SCAN_PATTERN = %r{(?:\A|/|_)(?:spec|test)\.rb\z|(?:\A|/)vendor/}

      # relative_path is relative to the project root, so a root inside a directory named
      # vendor doesn't skip everything.
      def skip_scan?(relative_path)
        relative_path.match?(SKIP_SCAN_PATTERN)
      end
    end

    def initialize(path, uri = nil)
      # Should probably lock for read, but I'm feeling crazy!
      self.class.root_path = path if self.class.root_path.nil?
      self.class.root_uri = uri if uri

      # The URI the editor uses for the project root. The scan maps container paths onto it.
      @root_uri = uri || "file://#{path}"
      # This is {uri: code_file} where content stuff is like
      # @additional_gems_installed = false
      # @additional_gem_mutex = Mutex.new
    end

    # def diagnostics_ready?
    #   @additional_gem_mutex.synchronize { @additional_gems_installed }
    # end

    # The prefix the background scan puts in front of each file's path relative to the
    # project root: the client's rootUri, or file:// + rootPath, with a trailing slash.
    def scan_root_uri
      @root_uri.end_with?('/') ? @root_uri : "#{@root_uri}/"
    end

    def text_for_uri(uri)
      code_file = code_file_for_uri(uri)
      code_file&.text || ''
    end

    def tags_for_uri(uri)
      code_file = code_file_for_uri(uri)
      return [] if code_file.nil?

      code_file.tags
    end

    def root_scope_for(uri)
      code_file_for_uri(uri).scopes.root_scope
    end

    # Return the list of scopes [deepest, parent, ..., Object]
    def scopes_at(uri, position)
      code_file = code_file_for_uri(uri)
      code_file.refresh_scopes_if_needed
      code_file.scopes.for_line(position.line + 1).where.not(path: nil).by_path_length
    end

    def completion_at(uri, position)
      context = context_at_location(uri, position)
      return nil if context.blank? # null: no completions

      position_scopes = scopes_at(uri, position)
      RubyLanguageServer.logger.debug("scopes_at(uri, position) #{position_scopes.map(&:name)}")
      # Outside every class, module, method and block, complete from the file's top level.
      position_scopes = RubyLanguageServer::ScopeData::Scope.where(id: root_scope_for(uri)&.id) if position_scopes.empty?
      context_scope = position_scopes.first
      RubyLanguageServer::Completion.completion(context, context_scope, position_scopes)
    end

    # How many times the background scan retries a file when the database is locked.
    SCAN_BUSY_RETRIES = 3
    SCAN_BUSY_RETRY_DELAY = 1 # seconds

    # Stores and parses one file for the background scan. attributes are extra CodeFile
    # columns, like gem_name for a gem's file. Only a locked database is retried, briefly;
    # any other error is raised for the caller to log.
    def index_file(uri, text, **attributes)
      attempts = 0
      begin
        ActiveRecord::Base.connection_pool.with_connection do
          update_document_content(uri, text)
          code_file = code_file_for_uri(uri)
          code_file.update_columns(attributes) if attributes.any? && code_file.persisted?
          code_file.refresh_scopes_if_needed
        end
      rescue ActiveRecord::StatementTimeout => e
        attempts += 1
        raise if attempts > SCAN_BUSY_RETRIES

        RubyLanguageServer.logger.warn("Database busy indexing #{uri}, retrying: #{e.message}")
        sleep scan_busy_retry_delay
        retry
      end
    end

    # The background scan runs niced, so editor requests get the CPU first.
    SCAN_NICENESS = 10

    def lower_priority
      Process.setpriority(Process::PRIO_PROCESS, 0, SCAN_NICENESS)
    rescue SystemCallError, NotImplementedError => e
      RubyLanguageServer.logger.warn("Couldn't lower the scan's priority: #{e}")
    end

    def scan_busy_retry_delay
      SCAN_BUSY_RETRY_DELAY
    end

    def scan_all_project_files
      project_ruby_files = Dir.glob("#{self.class.root_path}**/*.rb")
      RubyLanguageServer.logger.debug('Threading up!')
      root_uri = scan_root_uri
      # Using fork because this is run in a docker container that has fork.
      # If you want to run this on some platform without fork, fork the code and PR it :-)
      fork_id = fork do
        lower_priority
        project_ruby_files.each do |container_path|
          relative_path = container_path.delete_prefix(self.class.root_path)
          next if self.class.skip_scan?(relative_path)

          text = File.read(container_path)
          host_uri = root_uri + relative_path
          RubyLanguageServer.logger.debug("Threading #{host_uri}")
          index_file(host_uri, text)
        rescue StandardError => e
          # One bad file mustn't stall the scan: log it and go on to the next.
          RubyLanguageServer.logger.error("Skipping #{container_path}: #{e.class}: #{e}\n#{e.backtrace * "\n"}")
        end
        # Then Ruby core, then the gems, whose downloads are the slowest part.
        CoreIndex.index_project
        GemIndex.index_project(self.class.root_path, method(:index_file))
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

    # Returns the context of what is being typed in the given line
    def context_at_location(uri, position)
      code_file = code_file_for_uri(uri)
      code_file&.context_at_location(position)
    end

    # FileChangeType values in workspace/didChangeWatchedFiles.
    FILE_CREATED = 1
    FILE_CHANGED = 2
    FILE_DELETED = 3

    # Keeps the index in step with files created, changed or deleted outside the editor.
    def watched_files_changed(changes)
      changes.each do |change|
        uri = change['uri']
        case change['type']
        when FILE_DELETED then forget_uri(uri)
        when FILE_CREATED, FILE_CHANGED then reload_from_disk(uri)
        end
      rescue StandardError => e
        RubyLanguageServer.logger.error("Error handling watched file change #{change}: #{e.class}: #{e}")
      end
    end

    # Drops a file from the index. If uri is a directory, drops everything under it.
    def forget_uri(uri)
      under_directory = "#{ActiveRecord::Base.sanitize_sql_like(uri.delete_suffix('/'))}/%"
      CodeFile.where(uri:).or(CodeFile.where('uri LIKE ?', under_directory)).destroy_all
    end

    def reload_from_disk(uri)
      path = container_path_for(uri)
      return if path.nil? || !path.end_with?('.rb') || !File.file?(path)

      update_document_content(uri, File.read(path))
    end

    # Maps an editor URI under the project root to the path this server reads it from.
    # Returns nil for URIs outside the project.
    def container_path_for(uri)
      prefix = self.class.root_uri
      return nil if self.class.root_path.nil? || !uri.start_with?(prefix)

      File.join(self.class.root_path, URI.decode_uri_component(uri.delete_prefix(prefix)))
    end

    def word_at_location(uri, position)
      context_at_location(uri, position)&.last
    end

    # Locations of what the word at position refers to. Records with nowhere the editor can
    # open are left out: Ruby core (CoreIndex) has no code file, and gems' files (GemIndex)
    # are inside the container.
    def possible_definitions(uri, position)
      records_to_locations(definition_records(uri, position))
    end

    # The scopes and variables the word at position refers to, the project's own first.
    def definition_records(uri, position)
      context = context_at_location(uri, position)
      name = context&.last
      return [] if name.blank?

      # Special case: "new" should find "initialize" (instance method, not class method)
      name = 'initialize' if name == 'new'

      # Get current scopes for context
      current_scopes = scopes_at(uri, position)

      # If context has more than one element it could be a method call or namespace reference
      if context.length > 1
        # Find the rightmost class/module reference in the context (excluding the last element which is the name)
        # Examples:
        # - foo.Bar::Baz.something -> find Baz (index 2), build scope from Bar::Baz
        # - Bar.foo.Baz.something -> find Baz (index 2), use Baz as scope
        class_module_indices = []
        (0...(context.length - 1)).each do |i|
          class_module_indices << i if likely_class_name?(context[i])
        end

        if class_module_indices.any?
          # Find the continuous chain of class/module names ending at the rightmost one
          # For "Foo::Bar.method", we want both Foo and Bar, not just Bar
          # For "foo.Bar::Baz.method", we want Bar and Baz, not just Baz
          rightmost_class_index = class_module_indices.last

          # Find the leftmost index of the continuous chain ending at rightmost_class_index
          leftmost_continuous_index = rightmost_class_index
          class_module_indices.reverse.each_cons(2) do |right, left|
            break unless right == left + 1 # Break if not continuous

            leftmost_continuous_index = left
          end

          scope_path_parts = context[leftmost_continuous_index..-2]
          # A leading :: (::Foo::Bar) splits into an empty first element: top level only.
          top_level = leftmost_continuous_index.positive? && context[leftmost_continuous_index - 1] == ''

          # Resolve the receiver the way Ruby does: inside the enclosing namespaces first.
          receiver_scopes = resolve_constant_scopes(scope_path_parts.join('::'), current_scopes, top_level:)

          # Determine if it's a class/module lookup or a method call
          # If the name also looks like a class/module name, it's a namespace lookup (Foo::Bar)
          # Otherwise it's a method call (Foo.method or Foo::Bar.method)
          return receiver_definition_records(name, receiver_scopes) if likely_class_name?(name) || constant_name?(name)

          # Method call - determine if it's a class method or instance method
          class_method_filter = name != 'initialize'
          return receiver_definition_records(name, receiver_scopes, class_method_filter)

        end

        # No class/module found in chain, treat as instance method call on unknown type
        # Search project-wide for all instance methods with this name
        return project_definition_records(name, [], false)
      end

      # No receiver - search in scope chain first, then project-wide
      results = scope_variables_named(name, current_scopes.first)
      return results unless results.empty?

      project_definition_records(name, current_scopes)
    end

    # Hover for the word at position: the signature of the first definition that
    # definition_records finds, or nil.
    def hover_at(uri, position)
      record = definition_records(uri, position).first
      markdown = record && Hover.markdown(record)
      return nil if markdown.blank?

      { contents: { kind: 'markdown', value: markdown } }
    end

    # Return variables found in the current scope.  After all, those are the important ones.
    # Should probably be private...
    def scope_definitions_for(name, scope, uri)
      scope_variables_named(name, scope).map { |variable| Location.hash(uri, variable.line, variable.column.to_i) }
    end

    # class_method_filter is for new -> initialize
    def project_definitions_for(name, parent_scopes = [], class_method_filter = nil)
      records_to_locations(project_definition_records(name, parent_scopes, class_method_filter))
    end

    private

    # The variables named name in scope and the scopes around it, innermost first.
    def scope_variables_named(name, scope)
      matches = []
      check_scope = scope
      while check_scope
        matches.concat(check_scope.variables.select { |variable| variable.name == name })
        check_scope = check_scope.parent
      end
      matches
    end

    def project_definition_records(name, parent_scopes = [], class_method_filter = nil)
      # If no parent scope, search project-wide
      return search_project_wide(name, class_method_filter) if parent_scopes.empty?

      supplied_scope = parent_scopes.first

      # First pass: Look for variables (constants) in the scope chain
      result = search_variables_in_scope_chain(name, supplied_scope)
      return result if result.any?

      # Second pass: Look for child scopes in the scope chain
      result = search_child_scopes_in_chain(name, supplied_scope, class_method_filter)
      return result if result.any?

      # Fall back to project-wide search
      search_project_wide(name, class_method_filter)
    end

    # The project's own scopes and variables first, then the gems' (GemIndex), then Ruby
    # core's (CoreIndex), which have no file.
    def with_files_first(records)
      records = records.to_a
      # One query for all the records' files, not one per record.
      ActiveRecord::Associations::Preloader.new(records:, associations: :code_file).call
      records.each_with_index.sort_by { |record, index| [record.source_rank, index] }.map(&:first)
    end

    # Location hashes for the records that have a file the editor can open.
    def records_to_locations(records)
      with_files_first(records).select(&:project_record?).map do |record|
        line = record.respond_to?(:top_line) ? record.top_line : record.line
        Location.hash(record.code_file.uri, line, record.column.to_i)
      end
    end

    # Search for a variable/constant up the scope chain (first pass)
    # Variables in scope chain take priority over child scopes
    def search_variables_in_scope_chain(name, supplied_scope)
      current = supplied_scope
      while current
        # For constants, skip method scopes and keep searching up to class/module scopes
        if current.class_type == RubyLanguageServer::ScopeData::Scope::TYPE_METHOD
          current = current.parent
          next
        end

        # Check variables (constants) in the current scope
        matching_variable = with_files_first(current.variables.where(name: name)).find(&:code_file)
        return [matching_variable] if matching_variable

        current = current.parent
      end
      []
    end

    # Search for child scopes up the scope chain (second pass)
    def search_child_scopes_in_chain(name, supplied_scope, class_method_filter)
      current = supplied_scope
      while current
        # For constants, skip method scopes and keep searching up to class/module scopes
        if current.class_type == RubyLanguageServer::ScopeData::Scope::TYPE_METHOD
          current = current.parent
          next
        end

        # Check child scopes (classes/modules/methods) with this name, then, for a class,
        # its superclasses' before moving out to the enclosing scope, as Ruby does.
        [current, *(current.class_scope? ? current.ancestor_class_scopes : [])].each do |scope|
          child_scopes = scope.children.where(name: name)
          child_scopes = child_scopes.where(class_method: class_method_filter) unless class_method_filter.nil?
          return with_files_first(child_scopes) if child_scopes.any?
        end

        current = current.parent
      end
      []
    end

    # Search for a name project-wide (fallback)
    def search_project_wide(name, class_method_filter)
      all_scopes = RubyLanguageServer::ScopeData::Scope.where(name: name)
      all_scopes = all_scopes.where(class_method: class_method_filter) unless class_method_filter.nil?
      all_variables = RubyLanguageServer::ScopeData::Variable.where(name: name)
      with_files_first(all_scopes.to_a + all_variables.to_a)
    end

    # The scopes a constant path like "Bar" or "Bar::Baz" refers to from the cursor.
    # Like Ruby, try each enclosing class or module, innermost first, then the top
    # level. Inside Outer::Other, "Inner" tries Outer::Other::Inner, Outer::Inner, Inner.
    # Returns every scope with the first path that exists: a class reopened in several
    # files has one scope per file. Returns [] if nothing matches.
    #
    # This uses the nesting of scope paths, so `class Outer::Other` counts as being
    # inside Outer, which Ruby's lexical scope doesn't do.
    def resolve_constant_scopes(path, current_scopes, top_level: false)
      return [] if path.blank?

      namespaces = top_level ? [] : current_scopes.select { |scope| type_is_class_or_module?(scope) }.map(&:path)
      candidates = namespaces.map { |namespace| "#{namespace}::#{path}" } + [path]
      candidates.each do |candidate|
        scopes = RubyLanguageServer::ScopeData::Scope.where(path: candidate).to_a
        return scopes if scopes.any?
      end
      []
    end

    def type_is_class_or_module?(scope)
      [RubyLanguageServer::ScopeData::Base::TYPE_CLASS, RubyLanguageServer::ScopeData::Base::TYPE_MODULE].include?(scope.class_type)
    end

    # Definitions of name inside the receiver's scopes (and their parents), or anywhere
    # in the project if there are none.
    def receiver_definition_records(name, receiver_scopes, class_method_filter = nil)
      return search_project_wide(name, class_method_filter) if receiver_scopes.empty?

      results = receiver_scopes.flat_map { |scope| search_variables_in_scope_chain(name, scope) }
      results = receiver_scopes.flat_map { |scope| search_child_scopes_in_chain(name, scope, class_method_filter) } if results.empty?
      results = search_project_wide(name, class_method_filter) if results.empty?
      results.uniq
    end

    # Check if a name looks like a constant (all uppercase)
    def constant_name?(name)
      # Must start with uppercase letter and contain no lowercase letters
      return false unless /\A[A-Z]/.match?(name)

      !/[a-z]/.match?(name)
    end

    # Guess if a receiver name is likely a class name based on idiomatic Ruby conventions.
    # This is a heuristic and not 100% accurate (e.g., FOO could be a constant holding an instance).
    # Returns true for names like "Foo" or "FooBar" (starts with uppercase, has lowercase letters).
    # Returns false for "FOO" (all uppercase constant) or "foo" (variable/method).
    def likely_class_name?(name)
      # Must start with uppercase letter
      return false unless /[A-Z]/.match?(name[0])

      # Must contain at least one lowercase letter to distinguish from constants like FOO
      name =~ /[a-z]/
    end

    # The stored file for uri. For a URI the server hasn't seen, an unsaved, empty
    # CodeFile, so lookups don't write to the database; CodeFile#update_text saves it.
    def code_file_for_uri(uri)
      CodeFile.find_by(uri:) || CodeFile.new(uri:)
    end
  end
end
