# frozen_string_literal: true

require_relative '../../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::ScopeParserCommands::RakeCommands do
  describe 'Rakefile' do
    let(:rake_source) do
      <<-RAKE
      desc 'Run guard'
      task guard: [] do
        foo = 1
        `guard`
      end
      task :second do
      end
      task 'third' do
      end
      task "fourth" do
      end

      namespace :cadet do
        task something: [] do
        end
      end
      RAKE
    end
    let(:scope_parser) { RubyLanguageServer::ScopeParser.new(rake_source) }

    it 'should find a block with a variable' do
      # The first child is the task, the second one is the block of the task.
      # This is not a great test.
      assert_equal('foo', scope_parser.root_scope.self_and_descendants.where(name: RubyLanguageServer::ScopeData::Base::BLOCK_NAME).first.variables.first.name)
    end

    it 'should find namespaces and their tasks' do
      # The first child is the task, the second one is the block of the task.
      # This is not a great test.
      namespace_scope = scope_parser.root_scope.self_and_descendants.detect { |scope| scope.name == 'cadet' }
      refute_nil(namespace_scope)
      assert_equal(['block', 'something:', 'block'], namespace_scope.descendants.map(&:name).compact)
    end
  end
end
