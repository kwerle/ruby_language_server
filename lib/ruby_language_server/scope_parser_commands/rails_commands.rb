# frozen_string_literal: true

module RubyLanguageServer
  module ScopeParserCommands
    module RailsCommands
      def rails_add_reference(line, args, rest)
        # args: [:@ident, "has_one", [2, 2]]
        # rest: [[:args_add_block, [[:symbol_literal, [:symbol, [:@ident, "bar", [2, 11]]]]], false]]

        # Looks like the first string is gonna be the name
        (_, _, (_, column)) = args
        name = rest.flatten.detect { |o| o.instance_of? String }
        [name, "#{name}="].each do |method_name|
          push_scope(RubyLanguageServer::ScopeData::Base::TYPE_METHOD, method_name, line, column, line)
          pop_scope
        end
      end

      alias on_has_one_command                 rails_add_reference
      alias on_has_many_command                rails_add_reference
      alias on_belongs_to_command              rails_add_reference
      alias on_has_and_belongs_to_many_command rails_add_reference
      alias on_scope_command                   rails_add_reference
      alias on_named_scope_command             rails_add_reference
      # alias on_ xxx _command rails_add_reference
    end
  end
end
