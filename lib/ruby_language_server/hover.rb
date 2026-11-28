# frozen_string_literal: true

module RubyLanguageServer
  # Markdown for textDocument/hover, built from what the index already stores.
  module Hover
    class << self
      # A Scope (class, module or method) or a Variable.
      def markdown(record)
        case record
        when ScopeData::Variable then variable_markdown(record)
        when ScopeData::Scope then scope_markdown(record)
        end
      end

      private

      def scope_markdown(scope)
        markdown = case scope.class_type
                   when ScopeData::Base::TYPE_METHOD then method_markdown(scope)
                   when ScopeData::Base::TYPE_CLASS then code_block(['class', scope.path, superclass(scope)].compact.join(' '))
                   when ScopeData::Base::TYPE_MODULE then code_block("module #{scope.path}")
                   end
        # rdoc for Ruby core (CoreIndex), or the comment above a project definition.
        [markdown, gem_line(scope), scope.documentation.presence].compact.join("\n\n").presence
      end

      def superclass(scope)
        "< #{scope.superclass_name}" if scope.superclass_name.present?
      end

      def method_markdown(scope)
        receiver = scope.class_method ? 'self.' : ''
        return [code_block(rbs_signature(scope, receiver)), container_line(scope.parent)].compact.join("\n\n") if scope.signature.present?

        parameters = scope.parsed_parameters.map { |parameter| parameter_text(parameter) }
        signature = "def #{receiver}#{scope.name}"
        signature += "(#{parameters.join(', ')})" if parameters.any?
        [code_block(signature), container_line(scope.parent)].compact.join("\n\n")
      end

      # A Ruby core method's RBS overloads, one `def name: overload` line each.
      def rbs_signature(scope, receiver)
        scope.signature.lines(chomp: true).map { |overload| "def #{receiver}#{scope.name}: #{overload}" }.join("\n")
      end

      # Parameters are stored as { 'name' => ..., 'type' => ..., 'default' => ... } (see
      # PrismProcessor). Rest, keyword rest and block names already carry their *, ** or &,
      # and keyword names their trailing colon. Core parameters have no default.
      def parameter_text(parameter)
        case parameter['type']
        when 'optional' then "#{parameter['name']} = #{parameter['default'] || '…'}"
        when 'optional_keyword' then "#{parameter['name']} #{parameter['default'] || '…'}"
        else parameter['name']
        end
      end

      def variable_markdown(variable)
        [code_block(variable.name), "Defined in `#{variable.scope&.path.presence || 'top level'}`, line #{variable.line}", gem_line(variable)].compact.join("\n\n")
      end

      # Where a record from one of the project's gems (GemIndex) comes from.
      def gem_line(record)
        code_file = record.code_file
        "From gem `#{code_file.gem_name} #{code_file.gem_version}`" if code_file&.gem_file?
      end

      def container_line(scope)
        return nil if scope.nil? || scope.path.blank?

        "In `#{scope.path}`"
      end

      def code_block(code)
        "```ruby\n#{code}\n```"
      end
    end
  end
end
