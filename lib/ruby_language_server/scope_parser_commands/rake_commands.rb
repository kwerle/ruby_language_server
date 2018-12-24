# frozen_string_literal: true

module RubyLanguageServer
  module ScopeParserCommands
    module RakeCommands
      def on_task_command(line, args, rest)
        # OMG.  Rake commands can have like any form.
        # The most reliable way I can see to name them is to grab the string
        # I *so* do not want to hear about it when it doesn't work.
        name = rest.flatten.detect { |o| o.instance_of?(String) }
        # add_scope(args, rest, ScopeData::Scope::TYPE_METHOD)
        push_scope(ScopeData::Scope::TYPE_MODULE, name, line, 0, false)
        process(args)
        process(rest)
        # We push a scope and don't pop it because we're called inside on_method_add_block
      end
    end
  end
end
