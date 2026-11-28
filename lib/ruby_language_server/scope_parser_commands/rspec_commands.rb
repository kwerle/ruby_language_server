# frozen_string_literal: true

module RubyLanguageServer
  module ScopeParserCommands
    module RspecCommands
      def on_describe_command(node)
        rspec_block_command('describe', node)
      end

      def on_context_command(node)
        rspec_block_command('context', node)
      end

      def on_it_command(node)
        rspec_block_command('it', node)
      end

      # let(:foo) { ... } adds the variable foo to the current scope.
      def on_let_command(node)
        var_name = command_arguments(node).first
        return if var_name.nil?

        add_variable(var_name, command_line(node), command_column(node))
      end

      # let! is an eager version of let - alias it using send to avoid syntax issues
      send(:alias_method, 'on_let!_command', :on_let_command)

      private

      # Push the named scope (e.g., "describe Something").
      # The block node will create a child "block" scope automatically.
      # Signal that visit_call_node should pop this scope after visiting children.
      def rspec_block_command(prefix, node)
        name = "#{prefix} #{command_arguments(node).join('::')}"
        push_scope(ScopeData::Scope::TYPE_MODULE, name, command_line(node), 0, command_end_line(node))
        @command_pushed_scope = true
      end
    end
  end
end
