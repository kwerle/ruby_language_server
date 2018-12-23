# frozen_string_literal: true

module RubyLanguageServer
  module ScopeParserCommands
    module RspecCommands
      def on_describe_command(line, _args, rest)
        # byebug
        # add_scope(args, rest, ScopeData::Scope::TYPE_METHOD)
        name = rest.flatten.select { |part| part.instance_of?(String) }.join('::')
        push_scope(ScopeData::Scope::TYPE_MODULE, name, line, 0)
      end
    end
  end
end
