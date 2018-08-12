module RubyLanguageServer
  module Completion
    class << self

      def completion(context, context_scope, scopes)
        RubyLanguageServer.logger.error("completion(#{context}, #{context_scope.self_and_ancestors.map(&:name)}, #{scopes.map(&:name)})")
        if context.length < 2
          return scope_completions(context.last, context_scope.self_and_ancestors)
        else
          working_array = context.dup
          working_word = working_array.pop
          context_word = working_array.pop
          if context_word.match? /^[A-Z]/
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
      end

      def scope_with_name(name, scopes)
        scopes.detect{ |scope| scope.name == name }
      end

      def scope_completions(word, scopes)
        words = {}
        scopes.inject(words) do |words_hash, scope|
          scope.children.each{ |function| words_hash[function.name] ||= {
            depth: scope.depth,
            type: function.type,
            }
          }
          scope.variables.each{ |variable| words_hash[variable.name] ||= {
            depth: scope.depth,
            type: variable.type,
            }
          }
          words_hash
        end
        # words = words.sort_by{|word, hash| hash[:depth] }.to_h
        good_words = FuzzyMatch.new(words.keys, threshold: 0.01).find_all(word).slice(0..10) || []
        words = good_words.map{|w| [w, words[w]]}.to_h
      end

    end
  end
end
