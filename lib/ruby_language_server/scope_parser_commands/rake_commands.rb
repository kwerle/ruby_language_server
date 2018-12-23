# frozen_string_literal: true

module RubyLanguageServer
  module ScopeParserCommands
    module RakeCommands
      def on_task_command(line, _args, rest)
        # OMG.  Rake commands can have like any form.
        # The most reliable way I can see to name them is to grab the string
        # I *so* do not want to hear about it when it doesn't work.
        # byebug
        name = rest.flatten.detect { |o| o.instance_of?(String) }
        # add_scope(args, rest, ScopeData::Scope::TYPE_METHOD)
        push_scope(ScopeData::Scope::TYPE_METHOD, name, line, 0)
      end
    end
  end
end
