# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::LineContext do
  let(:line_context) { RubyLanguageServer::LineContext }

  describe 'basic variables' do
    let(:line) { 'foo = bar' }

    it "should find 'em'" do
      assert_equal(['foo'], line_context.for(line, 0))
    end

    it "should find 'em'" do
      assert_equal(['bar'], line_context.for(line, 6))
    end
  end

  describe 'dot variables' do
    let(:line) { 'instance.method = another_instance.something' }

    it 'should get the base' do
      assert_equal(['instance'], line_context.for(line, 2))
      assert_equal(['instance'], line_context.for(line, 3))
      assert_equal(['instance'], line_context.for(line, 6))
      assert_equal([], line_context.for(line, 16))
      assert_equal(['another_instance'], line_context.for(line, 18))
    end

    it 'should get the method' do
      assert_equal(%w[instance method], line_context.for(line, 9))
    end
  end

  describe '&. separator' do
    let(:line) { 'this&.that::SOMETHING' }

    it 'should do the right things' do
      assert_equal(['this'], line_context.for(line, 4))
      # assert_equal(['this', ''], line_context.for(line, 5))
      assert_equal(%w[this that], line_context.for(line, 6))
      assert_equal(%w[this that], line_context.for(line, 7))
      assert_equal(%w[this that SOMETHING], line_context.for(line, 17))
    end
  end

  describe 'Module relative with methods' do
    let(:line) { 'Some::Module.instance.method = Max::Mod.another_instance.something' }

    it 'should get the base' do
      assert_equal(['Some'], line_context.for(line, 1))
      assert_equal(['Some:'], line_context.for(line, 5))
      assert_equal(%w[Some Module], line_context.for(line, 6))
    end
  end

  describe 'instance variables' do
    let(:line) { '@foo = 1' }

    it "should include the '@' sign" do
      assert_equal(['@foo'], line_context.for(line, 0))
    end
  end
end
