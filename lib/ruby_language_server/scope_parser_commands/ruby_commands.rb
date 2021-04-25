# frozen_string_literal: true

module RubyLanguageServer
  module ScopeParserCommands
    module RubyCommands
      # when 'define_method', 'alias_method',
      #      'public_class_method', 'private_class_method',
      #      # "public", "protected", "private",
      #      /^attr_(accessor|reader|writer)$/
      #   # on_method_add_arg([:fcall, name], args[0])
      # when 'attr'
      #   # [[:args_add_block, [[:symbol_literal, [:symbol, [:@ident, "top", [3, 14]]]]], false]]
      #   ((_, ((_, (_, (_, name, (line, column))))))) = rest
      #   add_ivar("@#{name}", line, column)
      #   push_scope(ScopeData::Scope::TYPE_METHOD, name, line, column)
      #   pop_scope
      #   push_scope(ScopeData::Scope::TYPE_METHOD, "#{name}=", line, column)
      #   pop_scope

      def on_attr_command(line, args, rest)
        column = ruby_command_column(args)
        names = ruby_command_names(rest)
        ruby_command_add_attr(line, column, names, true, true)
      end

      def on_attr_accessor_command(line, args, rest)
        column = ruby_command_column(args)
        names = ruby_command_names(rest)
        ruby_command_add_attr(line, column, names, true, true)
      end

      def on_attr_reader_command(line, args, rest)
        column = ruby_command_column(args)
        names = ruby_command_names(rest)
        ruby_command_add_attr(line, column, names, true, false)
      end

      def on_attr_writer_command(line, args, rest)
        column = ruby_command_column(args)
        names = ruby_command_names(rest)
        ruby_command_add_attr(line, column, names, false, true)
      end

      private

      def ruby_command_names(rest)
        rest.flatten.select { |o| o.instance_of? String }
      end

      def ruby_command_column(args)
        (_, _, (_, column)) = args
        column
      end

      def ruby_command_add_attr(line, column, names, reader, writer)
        names.each do |name|
          if reader
            push_scope(RubyLanguageServer::ScopeData::Base::TYPE_METHOD, name, line, column)
            pop_scope
          end
          if writer
            push_scope(RubyLanguageServer::ScopeData::Base::TYPE_METHOD, "#{name}=", line, column)
            pop_scope
          end
        end
      end
    end
  end
end
