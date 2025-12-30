# frozen_string_literal: true

require_relative '../../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::ScopeParserCommands::RubyCommands do
  before do
    @code_file_lines = <<-SOURCE
      class ModelClass
        attr_reader :something_else, :something_else2
        attr :read_write

        # These are fcalls.  I'm not yet doing this.
        define_method(:add_one) { |arg| arg + 1 }
        define_method(:add_another, method(:add_one))
      end
    SOURCE

    @parser = RubyLanguageServer::ScopeParser.new(@code_file_lines)
  end

  let(:class_scope) { RubyLanguageServer::ScopeData::Scope.find_by_name('ModelClass') }

  describe 'attr_reader' do
    it 'should have appropriate functions' do
      # class_scope = @parser.root_scope.children.first
      assert_equal(['something_else', 'something_else2', 'read_write', 'read_write=', 'block'], class_scope.children.map(&:name))
    end
  end

  describe 'attr' do
    it 'should have appropriate functions' do
      # class_scope = @parser.root_scope.children.first
      assert_equal(['something_else', 'something_else2', 'read_write', 'read_write='], class_scope.children.map(&:name))
    end
  end
end
