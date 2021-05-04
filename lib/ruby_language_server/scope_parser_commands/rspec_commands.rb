# frozen_string_literal: true

module RubyLanguageServer
  module ScopeParserCommands
    module RspecCommands
      def on_describe_command(line, args, rest)
        rspec_block_command('describe', line, args, rest)
      end

      def on_context_command(line, args, rest)
        rspec_block_command('context', line, args, rest)
      end

      def on_it_command(line, args, rest)
        rspec_block_command('it', line, args, rest)
      end

      private

      def rspec_block_command(prefix, line, args, rest)
        name = "#{prefix} "
        name += rest.flatten.select { |part| part.instance_of?(String) }.join('::')
        push_scope(ScopeData::Scope::TYPE_MODULE, name, line, 0, false)
        process(args)
        process(rest)
        # We push a scope and don't pop it because we're called inside on_method_add_block
      end
    end
  end
end
