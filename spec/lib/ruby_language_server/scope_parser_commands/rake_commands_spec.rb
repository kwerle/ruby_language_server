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
      RAKE
    end
    let(:scope_parser) { RubyLanguageServer::ScopeParser.new(rake_source) }

    it 'should find a block with a variable' do
      # The first child is the task, the second one is the block of the task.
      # This is not a great test.
      assert_equal('foo', scope_parser.root_scope.self_and_descendants[2].variables.first.name)
    end
  end
end
