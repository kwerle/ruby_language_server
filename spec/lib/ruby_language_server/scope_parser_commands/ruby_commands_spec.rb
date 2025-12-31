# frozen_string_literal: true

require_relative '../../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::ScopeParserCommands::RubyCommands do
  before do
    @code_file_lines = <<-SOURCE
      class ModelClass
        attr_reader :something_else, :something_else2
        attr :read_write
        attr_accessor :name, :age
        attr_writer :secret, :password

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
      method_names = class_scope.children.map(&:name)
      assert_includes method_names, 'something_else'
      assert_includes method_names, 'something_else2'
    end
  end

  describe 'attr' do
    it 'should have appropriate functions for read and write' do
      method_names = class_scope.children.map(&:name)
      assert_includes method_names, 'read_write'
      assert_includes method_names, 'read_write='
    end
  end

  describe 'attr_accessor' do
    it 'should create both reader and writer methods' do
      method_names = class_scope.children.map(&:name)
      
      # Should have both getter and setter for each attribute
      assert_includes method_names, 'name'
      assert_includes method_names, 'name='
      assert_includes method_names, 'age'
      assert_includes method_names, 'age='
    end
  end

  describe 'attr_writer' do
    it 'should create only writer methods' do
      method_names = class_scope.children.map(&:name)
      
      # Should only have setters, not getters
      assert_includes method_names, 'secret='
      assert_includes method_names, 'password='
      refute_includes method_names, 'secret'
      refute_includes method_names, 'password'
    end
  end
end
