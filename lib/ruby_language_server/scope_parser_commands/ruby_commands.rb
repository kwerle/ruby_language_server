# frozen_string_literal: true

module RubyLanguageServer
  module ScopeParserCommands
    module RubyCommands
      # attr :foo and attr_accessor :foo add the methods foo and foo=.
      def on_attr_command(node)
        ruby_command_add_attr(node, reader: true, writer: true)
      end

      def on_attr_accessor_command(node)
        ruby_command_add_attr(node, reader: true, writer: true)
      end

      def on_attr_reader_command(node)
        ruby_command_add_attr(node, reader: true, writer: false)
      end

      def on_attr_writer_command(node)
        ruby_command_add_attr(node, reader: false, writer: true)
      end

      private

      def ruby_command_add_attr(node, reader:, writer:)
        line = command_line(node)
        column = command_column(node)
        command_arguments(node).each do |name|
          next if name.blank?

          if reader
            push_scope(RubyLanguageServer::ScopeData::Base::TYPE_METHOD, name, line, column, line)
            pop_scope
          end
          next unless writer

          writer_scope = push_scope(RubyLanguageServer::ScopeData::Base::TYPE_METHOD, "#{name}=", line, column, line)
          writer_scope.assign_parameters([{name: 'value', type: 'required'}])
          pop_scope
        end
      end
    end
  end
end
