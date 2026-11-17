# frozen_string_literal: true

require_relative '../../../test_helper'
require 'minitest/autorun'

describe 'ScopeParserCommands helpers' do
  # The last statement in the source (the command call), and a processor to ask about it.
  def call_in(source)
    node = Prism.parse(source).value.statements.body.last
    [RubyLanguageServer::PrismProcessor.new, node]
  end

  def arguments_of(source)
    processor, node = call_in(source)
    processor.send(:command_arguments, node)
  end

  it 'reads symbols, strings and constants in order' do
    assert_equal(%w[a b], arguments_of('attr_reader :a, :b'))
    assert_equal(['Some::Class', 'does things'], arguments_of("describe Some::Class, 'does things'"))
    assert_equal(['thing'], arguments_of('describe Thing.new, "thing"')) # other expressions are skipped
  end

  it 'reads keyword hash keys with a trailing colon' do
    assert_equal(['something:'], arguments_of('task something: [:other]'))
  end

  it 'is empty without arguments' do
    assert_equal([], arguments_of('has_many'))
  end

  it 'reports the line and the UTF-16 column of the call' do
    processor, node = call_in("x = 'é'; attr_reader :a")
    assert_equal(1, processor.send(:command_line, node))
    assert_equal(9, processor.send(:command_column, node))
  end

  it 'adds no method for a reference with no name' do
    RubyLanguageServer::ScopeParser.new("class Foo\n  has_many\nend\n")
    assert_equal(['Foo'], RubyLanguageServer::ScopeData::Scope.where.not(class_type: 'root').pluck(:path))
  end
end
