# frozen_string_literal: true

module RubyLanguageServer
  module ScopeParserCommands
    module RailsCommands
      # has_one :bar adds the methods bar and bar=.
      def rails_add_reference(node)
        name = command_arguments(node).first
        return if name.nil?

        line = command_line(node)
        column = command_column(node)
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
