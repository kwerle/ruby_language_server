# frozen_string_literal: true

module RubyLanguageServer
  module Completion
    CompletionItemKind = {
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
        RubyLanguageServer.logger.error("completion(#{context}, #{context_scope.self_and_ancestors.map(&:name)}, #{scopes.map(&:name)})")
        completions = if context.length < 2
                        scope_completions(context.last, context_scope.self_and_ancestors)
                      else
                        working_array = context.dup
                        context_word = working_array.pop
                        if context_word.match?(/^[A-Z]/)
                          scope = scope_with_name(context_word, scopes)
                        else
                          context_word = context_word.split(/_/).map(&:capitalize).join('')
                          scope = scope_with_name(context_word, scopes)
                          RubyLanguageServer.logger.error("scope_with_name: #{scope&.name}")
                        end
                        scope ||= context_scope
                        RubyLanguageServer.logger.error("scope: #{scope&.name}")
                        scope_completions(context.last, scope.self_and_ancestors)
                      end
        {
          isIncomplete: true,
          items: completions.map do |word, hash|
            {
              label: word,
              kind: CompletionItemKind[hash[:type]]
            }
          end
        }
      end

      def scope_with_name(name, scopes)
        scopes.detect { |scope| scope.name == name }
      end

      def scope_completions(word, scopes)
        words = {}
        scopes.each_with_object(words) do |scope, words_hash|
          scope.children.each do |function|
            words_hash[function.name] ||= {
              depth: scope.depth,
              type: function.type
            }
          end
          scope.variables.each do |variable|
            words_hash[variable.name] ||= {
              depth: scope.depth,
              type: variable.type
            }
          end
        end
        # words = words.sort_by{|word, hash| hash[:depth] }.to_h
        good_words = FuzzyMatch.new(words.keys, threshold: 0.01).find_all(word).slice(0..10) || []
        words = good_words.map { |w| [w, words[w]] }.to_h
      end
    end
  end
end
