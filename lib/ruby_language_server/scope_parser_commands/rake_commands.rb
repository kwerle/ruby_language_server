# frozen_string_literal: true

module RubyLanguageServer
  module ScopeParserCommands
    module RakeCommands
      def on_task_command(node)
        rake_block_command(node)
      end

      def on_namespace_command(node)
        rake_block_command(node)
      end

      private

      # OMG.  Rake commands can have like any form.
      # The most reliable way I can see to name them is to grab the first name-like argument.
      # I *so* do not want to hear about it when it doesn't work.
      # Push the named scope - the block node will create a child "block" scope.
      def rake_block_command(node)
        name = command_arguments(node).first
        push_scope(ScopeData::Scope::TYPE_MODULE, name, command_line(node), 0, command_end_line(node))
        @command_pushed_scope = true
      end
    end
  end
end
