module RubyLanguageServer
  module Completion
    class << self

      def completion(context, context_scope, scopes)
        # RubyLanguageServer.logger.error("completion(#{context}, #{context_scope.map(&:name)}, #{scopes.map(&:name)})")
        scope_completions(context, scopes)
      end

      def scope_completions(context, scopes)
        word = context.last
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
