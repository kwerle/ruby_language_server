# frozen_string_literal: true

require 'rbs'

module RubyLanguageServer
  # Ruby's core classes and modules (String, Array, Kernel, ...), read from the RBS core
  # signatures and stored as ordinary scopes, so completion and hover know about them.
  #
  # The .rbs files are inside the container, where the editor can't open them, so these
  # scopes store no location: no code file and no lines. Go-to-definition only returns
  # records with a code file, so it leaves them out, and hover still finds them.
  module CoreIndex
    # Signatures say ::String for a top-level name. Drop the leading :: so hover reads
    # like Ruby. A :: after a name (File::Stat) stays.
    TOP_LEVEL_PREFIX = /(?<![\w\]])::(?=[A-Za-z_])/

    # The call-seq block rdoc puts at the top of each comment.
    RDOC_HEADER = /\A\s*<!--.*?-->\s*/m

    class << self
      # Stores the core scopes, unless they are already stored. only limits it to some
      # classes and modules, like %w[String Integer], so specs don't store all of core.
      def load!(only: nil)
        return if loaded?

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        classes = only ? class_entries.slice(*only) : class_entries
        ActiveRecord::Base.transaction do
          class_ids = insert_class_scopes(classes)
          rows = classes.flat_map { |path, entry| method_rows(path, class_ids.fetch(path), entry) }
          rows.each_slice(1000) { |slice| ScopeData::Scope.insert_all!(slice) }
        end
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        RubyLanguageServer.logger.info("Indexed Ruby core classes in #{elapsed.round(2)}s")
      end

      # Core scopes are the only ones with a signature.
      def loaded?
        ScopeData::Scope.where(code_file_id: nil).where.not(signature: nil).exists?
      end

      private

      # { 'File::Stat' => entry }. An entry can be declared in several files, and lists each
      # declaration. Parsing the signatures takes
      # a couple of seconds, so it's done once per process.
      def class_entries
        @class_entries ||= begin
          loader = RBS::EnvironmentLoader.new(core_root: RBS::EnvironmentLoader::DEFAULT_CORE_ROOT)
          RBS::Environment.from_loader(loader).class_decls.transform_keys { |type_name| type_name.to_s.delete_prefix('::') }
        end
      end

      # Inserts one scope per class or module, a level of nesting at a time so each parent's
      # id is known. Returns { path => id }.
      def insert_class_scopes(classes)
        ids = {}
        classes.group_by { |path, _entry| path.count(':') }.sort.each do |_depth, level|
          rows = level.map { |path, entry| class_row(path, entry, ids) }
          ScopeData::Scope.insert_all!(rows)
          ids.merge!(ScopeData::Scope.where(code_file_id: nil, path: level.map(&:first)).pluck(:path, :id).to_h)
        end
        ids
      end

      def class_row(path, entry, ids)
        declarations = declarations_of(entry)
        namespace, _, name = path.rpartition('::')
        {
          parent_id: ids[namespace],
          name:,
          path:,
          class_type: declarations.first.is_a?(RBS::AST::Declarations::Module) ? ScopeData::Base::TYPE_MODULE : ScopeData::Base::TYPE_CLASS,
          superclass_name: superclass_name(declarations, namespace),
          documentation: declarations.filter_map { |declaration| documentation(declaration.comment) }.first
        }
      end

      def declarations_of(entry)
        declarations = []
        entry.each_decl { |declaration| declarations << declaration }
        declarations
      end

      # Qualified with the namespace the way the parser does it (see Scope#set_superclass_name),
      # so Scope#superclass_scopes falls back to outer namespaces.
      def superclass_name(declarations, namespace)
        super_class = declarations.filter_map { |declaration| declaration.try(:super_class) }.first
        return nil if super_class.nil?

        written = super_class.name.to_s
        return written.delete_prefix('::') if written.start_with?('::') || namespace.empty?

        "#{namespace}::#{written}"
      end

      # Every method and alias in the class's declarations. A method declared in more than one
      # file is stored once.
      def method_rows(class_path, class_id, entry)
        members = declarations_of(entry).flat_map(&:members)
        definitions = members.grep(RBS::AST::Members::MethodDefinition).uniq { |definition| [definition.name, definition.kind] }
        by_name = definitions.to_h { |definition| [[definition.name, definition.singleton?], definition] }
        aliases = members.grep(RBS::AST::Members::Alias).filter_map do |alias_member|
          original = by_name[[alias_member.old_name, alias_member.singleton?]]
          [alias_member.new_name, original] if original
        end
        named = definitions.map { |definition| [definition.name, definition] } + aliases
        named.uniq { |name, definition| [name, definition.kind] }.flat_map do |name, definition|
          method_rows_for(class_path, class_id, definition, name)
        end
      end

      # A module_function (self?.) method is both an instance method and a class method.
      def method_rows_for(class_path, class_id, definition, name)
        class_methods = case definition.kind
                        when :instance then [false]
                        when :singleton then [true]
                        else [false, true]
                        end
        class_methods.map do |class_method|
          {
            parent_id: class_id,
            name: name.to_s,
            path: "#{class_path}#{ScopeData::Base::JoinHash[ScopeData::Base::TYPE_METHOD]}#{name}",
            class_type: ScopeData::Base::TYPE_METHOD,
            class_method:,
            parameters: parameters(definition.overloads.first&.method_type)&.to_json,
            signature: definition.overloads.map { |overload| readable(overload.method_type.to_s) }.join("\n"),
            documentation: documentation(definition.comment)
          }
        end
      end

      # The first overload's parameters, in the { name:, type: } form the parser stores.
      def parameters(method_type)
        function = method_type&.type
        return nil unless function.is_a?(RBS::Types::Function)

        params = function.required_positionals.map { |param| { name: param_name(param), type: 'required' } }
        params += function.optional_positionals.map { |param| { name: param_name(param), type: 'optional' } }
        params << { name: "*#{param_name(function.rest_positionals)}", type: 'rest' } if function.rest_positionals
        params += function.trailing_positionals.map { |param| { name: param_name(param), type: 'required' } }
        params += function.required_keywords.keys.map { |key| { name: "#{key}:", type: 'keyword' } }
        params += function.optional_keywords.keys.map { |key| { name: "#{key}:", type: 'keyword' } }
        params << { name: "**#{param_name(function.rest_keywords)}", type: 'keyword_rest' } if function.rest_keywords
        params << { name: '&block', type: 'block' } if method_type.block
        params.presence
      end

      # RBS parameters often have only a type, like (::string, ?int). Name those after the
      # type: string, int.
      def param_name(param)
        return param.name.to_s if param.name

        type = param.type
        type = type.type while type.is_a?(RBS::Types::Optional)
        return 'arg' unless type.respond_to?(:name)

        type.name.name.to_s.delete_prefix('_').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
      end

      def documentation(comment)
        return nil if comment.nil?

        comment.string.sub(RDOC_HEADER, '').strip.presence
      end

      def readable(signature)
        signature.gsub(TOP_LEVEL_PREFIX, '')
      end
    end
  end
end
