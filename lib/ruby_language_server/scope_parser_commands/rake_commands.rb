# frozen_string_literal: true

module RubyLanguageServer
  module ScopeParserCommands
    module RakeCommands
      def on_task_command(line, args, rest)
        # OMG.  Rake commands can have like any form.
        # The most reliable way I can see to name them is to grab the string
        # I *so* do not want to hear about it when it doesn't work.
        name = rest.flatten.detect { |o| o.instance_of?(String) }
        # Push the named scope - the block node will create a child "block" scope
        push_scope(ScopeData::Scope::TYPE_MODULE, name, line, 0, false)
        @command_pushed_scope = true
      end

      def on_namespace_command(line, args, rest)
        # OMG.  Rake commands can have like any form.
        # The most reliable way I can see to name them is to grab the string
        # I *so* do not want to hear about it when it doesn't work.
        name = rest.flatten.detect { |o| o.instance_of?(String) }
        # Push the named scope - the block node will create a child "block" scope
        push_scope(ScopeData::Scope::TYPE_MODULE, name, line, 0, false)
        @command_pushed_scope = true
      end
    end
  end
end
