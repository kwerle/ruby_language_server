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

      def on_let_command(line, args, rest)
        # Extract the variable name from the symbol (e.g., :foo -> foo)
        var_name = rest.flatten.first
        return unless var_name.is_a?(String)

        # Get the column from the args
        (_, _, (_, column)) = args
        
        # Add the variable to the current scope
        add_variable(var_name, line, column)
      end

      private

      def rspec_block_command(prefix, line, _args, rest)
        name = "#{prefix} "
        name += rest.flatten.select { |part| part.instance_of?(String) }.join('::')

        # Push the named scope (e.g., "describe Something")
        # The block node will create a child "block" scope automatically
        # Signal that visit_call_node should pop this scope after visiting children
        end_line = @current_block_node ? @current_block_node.location.end_line : line
        push_scope(ScopeData::Scope::TYPE_MODULE, name, line, 0, end_line, false)
        @command_pushed_scope = true
      end
    end
  end
end
