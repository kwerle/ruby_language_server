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
            scope_completions(context.last, scopes)
          else
            scope_completions_in_target_context(context, context_scope, scopes)
          end
        {
          isIncomplete: true,
          items: completions.uniq.map do |word, hash|
            {
              label: word,
              kind: COMPLETION_ITEM_KIND[hash[:type]]
            }
          end
        }
      end

      def scope_with_name(name, scopes)
        return scopes.where(name: name).first if scopes.respond_to?(:where)

        scopes.detect { |scope| scope.name == name }
      end

      def scope_completions_in_target_context(context, context_scope, scopes)
        context_word = context[-2]
        if context_word.match?(/^[A-Z]/)
          scope = scope_with_name(context_word, scopes)
        else
          context_word = context_word.split(/_/).map(&:capitalize).join('')
          scope = scope_with_name(context_word, scopes)
          RubyLanguageServer.logger.debug("scope_with_name: #{scope}")
        end
        scope ||= context_scope
        RubyLanguageServer.logger.debug("scope: #{scope.to_json}")
        scope_completions(context.last, [scope] + scopes.includes(:variables))
      end

      def scope_completions(word, scopes)
        words = {}
        scopes.each_with_object(words) do |scope, words_hash|
          scope.children.method_scopes.each do |method_scope|
            words_hash[method_scope.name] ||= {
              depth: scope.depth,
              type: method_scope.class_type
            }
          end
          scope.variables.each do |variable|
            words_hash[variable.name] ||= {
              depth: scope.depth,
              type: variable.variable_type
            }
          end
        end
        words = words.sort_by { |_word, hash| hash[:depth] }.to_h
        good_words = FuzzyMatch.new(words.keys, threshold: 0.01).find_all(word).slice(0..10) || []
        words = good_words.map { |w| [w, words[w]] }.to_h
      end
    end
  end
end
