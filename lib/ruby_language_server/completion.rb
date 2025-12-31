# frozen_string_literal: true

module RubyLanguageServer
  module Completion
    COMPLETION_ITEM_KIND = {
      text: 1,
      method: 2,
      function: 3,
      constructor: 4,
      field: 5,
      variable: 6,
      class: 7,
      interface: 8,
      module: 9,
      property: 10,
      unit: 11,
      value: 12,
      enum: 13,
      keyword: 14,
      snippet: 15,
      color: 16,
      file: 17,
      reference: 18
    }.freeze

    class << self
      def completion(context, context_scope, position_scopes)
        RubyLanguageServer.logger.debug("completion(#{context}, #{position_scopes.map(&:name)})")
        completions =
          if context.length < 2
            scope_completions(context.first, position_scopes)
          else
            scope_completions_in_target_context(context, context_scope, position_scopes)
          end
        # RubyLanguageServer.logger.debug("completions: #{completions.as_json}")
        {
          isIncomplete: true,
          items: completions.uniq.map do |word, hash|
            item = {
              label: word,
              kind: COMPLETION_ITEM_KIND[hash[:type]&.to_sym]
            }

            # Add snippet for methods with parameters
            if hash[:type] == 'method' && hash[:parameters]&.any?
              item[:insertText] = generate_method_snippet(word, hash[:parameters])
              item[:insertTextFormat] = 2 # Snippet format
            end

            item
          end
        }
      end

      private

      def generate_method_snippet(method_name, parameters)
        return method_name if parameters.empty?

        # Build snippet with tab stops
        param_snippets = []
        tab_index = 1

        parameters.each do |param|
          param_snippets << case param['type']
                            when 'keyword'
                              # Keyword args with placeholder for value
                              "#{param['name']} ${#{tab_index}:value}"
                            else
                              # All other param types use the parameter name
                              "${#{tab_index}:#{param['name']}}"
                            end
          tab_index += 1
        end

        "#{method_name}(#{param_snippets.join(', ')})"
      end

      def scopes_with_name(name, scopes)
        return scopes.where(name:) if scopes.respond_to?(:where)

        scopes.select { |scope| scope.name == name }
      end

      def scope_completions_in_target_context(context, context_scope, scopes)
        context_word = context[-2]
        context_word = context_word.split('_').map(&:capitalize).join unless context_word.match?(/^[A-Z]/)
        context_scopes = RubyLanguageServer::ScopeData::Scope.where(name: context_word)
        context_scopes ||= context_scope
        RubyLanguageServer.logger.debug("context_scopes: #{context_scopes.to_json}")
        # scope_completions(context.last, Array(context_scopes) + scopes.includes(:variables))
        (scope_completions(context.last, Array(context_scopes)).to_a + scope_completions(context.last, scopes.includes(:variables)).to_a).uniq.to_h
      end

      def module_completions(word)
        class_and_module_types = [RubyLanguageServer::ScopeData::Base::TYPE_CLASS, RubyLanguageServer::ScopeData::Base::TYPE_MODULE]

        # scope_words = RubyLanguageServer::ScopeData::Scope.where(class_type: class_and_module_types).sort_by(&:depth).map { |scope| [scope.name, scope] }
        # words = scope_words.to_h
        # good_words = FuzzyMatch.new(words.keys, threshold: 0.01).find_all(word).slice(0..10) || []
        # words = good_words.each_with_object({}) { |w, hash| hash[w] = {depth: words[w].depth, type: words[w].class_type} }.to_h

        words = RubyLanguageServer::ScopeData::Scope.where(class_type: class_and_module_types).closest_to(word).limit(20)
        RubyLanguageServer.logger.error("module_completions: #{words.as_json}")
        # words.to_a.sort_by(&:depth).each_with_object({}){|a_word, hash| hash[a_word.name] = {depth: a_word.depth, type: a_word.class_type} }
        good_words = FuzzyMatch.new(words.to_a, read: :name, threshold: 0.01).find_all(word).slice(0..10) || []
        good_words.each_with_object({}) { |w, hash| hash[w.name] = {depth: w.depth, type: w.class_type} }.to_h
      end

      def scope_completions(word, scopes)
        return module_completions(word) if word.match?(/\A[A-Z][a-z]/)

        scope_ids = scopes.map(&:id)
        word_scopes = scopes.to_a + RubyLanguageServer::ScopeData::Scope.where(parent_id: scope_ids).closest_to(word).limit(5)
        scope_words = word_scopes.select(&:named_scope?).sort_by(&:depth).map { |scope| [scope.name, scope] }
        variable_words = RubyLanguageServer::ScopeData::Variable.where(scope_id: scope_ids).closest_to(word).limit(5).map { |variable| [variable.name, variable.scope] }
        words = (scope_words + variable_words).to_h
        good_words = FuzzyMatch.new(words.keys, threshold: 0.01).find_all(word).slice(0..10) || []
        good_words.each_with_object({}) do |w, hash|
          scope = words[w]
          hash[w] = {depth: scope.depth, type: scope.class_type}
          # Include parameters for methods
          hash[w][:parameters] = scope.parsed_parameters if scope.method? && scope.parameters.present?
        end
      end
    end
  end
end
