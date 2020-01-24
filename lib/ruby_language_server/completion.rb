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
      def completion(context, context_scope, scopes)
        RubyLanguageServer.logger.debug("completion(#{context}, #{scopes.map(&:name)})")
        completions =
          if context.length < 2
            scope_completions(context.first, scopes)
          else
            scope_completions_in_target_context(context, context_scope, scopes)
          end
        RubyLanguageServer.logger.debug("completions: #{completions.as_json}")
        {
          isIncomplete: true,
          items: completions.uniq.map do |word, hash|
            {
              label: word,
              kind: COMPLETION_ITEM_KIND[hash[:type]&.to_sym]
            }
          end
        }
      end

      private

      def scopes_with_name(name, scopes)
        return scopes.where(name: name) if scopes.respond_to?(:where)

        scopes.select { |scope| scope.name == name }
      end

      def scope_completions_in_target_context(context, context_scope, scopes)
        context_word = context[-2]
        context_word = context_word.split(/_/).map(&:capitalize).join('') unless context_word.match?(/^[A-Z]/)
        context_scopes = scopes_with_name(context_word, scopes)
        context_scopes ||= context_scope
        RubyLanguageServer.logger.debug("context_scopes: #{context_scopes.to_json}")
        # scope_completions(context.last, Array(context_scopes) + scopes.includes(:variables))
        (scope_completions(context.last, Array(context_scopes)).to_a + scope_completions(context.last, scopes.includes(:variables)).to_a).uniq.to_h
      end

      def scope_completions(word, scopes)
        # words = {}
        # scopes.each_with_object(words) do |scope, words_hash|
        #   scope.children.method_scopes.each do |method_scope|
        #     words_hash[method_scope.name] ||= {
        #       depth: scope.depth,
        #       type: method_scope.class_type
        #     }
        #   end
        #   scope.variables.each do |variable|
        #     words_hash[variable.name] ||= {
        #       depth: scope.depth,
        #       type: variable.variable_type
        #     }
        #   end
        # end
        scope_ids = scopes.map(&:id)
        word_scopes = scopes.to_a + RubyLanguageServer::ScopeData::Scope.where(parent_id: scope_ids)
        scope_words = word_scopes.select(&:named_scope?).sort_by(&:depth).map{|scope| [scope.name, scope]}
        variable_words = RubyLanguageServer::ScopeData::Variable.where(scope_id: scope_ids).map{|variable| [variable.name, variable.scope]}
        words = (scope_words + variable_words).to_h
        good_words = FuzzyMatch.new(words.keys, threshold: 0.01).find_all(word).slice(0..10) || []
        words = good_words.each_with_object({}) { |word, hash| hash[word] = {depth: words[word].depth, type: words[word].class_type} }.to_h
      end
    end
  end
end
