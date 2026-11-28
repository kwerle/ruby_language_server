# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::Hover do
  let(:project_manager) { RubyLanguageServer::ProjectManager.new('/proj', 'file:///foo/') }
  let(:source) do
    <<~RUBY
      module Shop
        LIMIT = 10

        class Cart < Base
          def add(item, count = 1, *rest, key:, **options, &block)
          end

          def self.empty
          end
        end
      end

      cart = Shop::Cart.new
      cart.add(1)
      Shop::Cart.empty
      Shop::LIMIT
      cart
    RUBY
  end

  before do
    project_manager.update_document_content('hover_uri', source)
    project_manager.tags_for_uri('hover_uri') # parse it
  end

  def hover(line, character)
    project_manager.hover_at('hover_uri', OpenStruct.new(line:, character:))&.dig(:contents, :value)
  end

  it 'shows a method signature and where it is defined' do
    assert_equal("```ruby\ndef add(item, count = 1, *rest, key:, **options, &block)\n```\n\nIn `Shop::Cart`", hover(13, 6))
  end

  it 'marks class methods' do
    assert_equal("```ruby\ndef self.empty\n```\n\nIn `Shop::Cart`", hover(14, 12))
  end

  it 'shows a class with its superclass' do
    assert_equal("```ruby\nclass Shop::Cart < Shop::Base\n```", hover(12, 14))
  end

  it 'shows a module' do
    assert_equal("```ruby\nmodule Shop\n```", hover(12, 8))
  end

  it 'shows where a constant is defined' do
    assert_equal("```ruby\nLIMIT\n```\n\nDefined in `Shop`, line 2", hover(15, 7))
  end

  it 'shows where a local variable is defined' do
    assert_equal("```ruby\ncart\n```\n\nDefined in `top level`, line 13", hover(16, 1))
  end

  it 'returns nil on a blank line' do
    assert_nil(project_manager.hover_at('hover_uri', OpenStruct.new(line: 11, character: 0)))
  end

  describe 'with a method in several classes and an unknown receiver' do
    let(:source) do
      <<~RUBY
        class Dog
          # Woof.
          def speak(loud)
          end
        end

        class Cat
          def speak
          end
        end
        pet.speak
      RUBY
    end

    it 'lists each one, without documentation' do
      assert_equal("```ruby\ndef speak(loud)\n```\n\nIn `Dog`\n\n```ruby\ndef speak\n```\n\nIn `Cat`", hover(10, 6))
    end
  end

  describe 'with doc comments' do
    let(:source) do
      <<~RUBY
        # frozen_string_literal: true

        # A shopping cart.
        class Cart
          # Adds an item.
          #
          # Returns the cart.
          def add(item, *, size: :medium)
          end
        end
        cart = Cart.new
        cart.add(1)
      RUBY
    end

    it 'shows the comment above a method, with optional keywords and their defaults' do
      assert_equal("```ruby\ndef add(item, *, size: :medium)\n```\n\nIn `Cart`\n\nAdds an item.\n\nReturns the cart.", hover(11, 6))
    end

    it 'shows the comment above a class, without the magic comment' do
      assert_equal("```ruby\nclass Cart\n```\n\nA shopping cart.", hover(10, 8))
    end
  end

  describe 'from a gem' do
    before do
      project_manager.index_file('file:///data/gems/tiny-0.1.0/lib/tiny.rb', "# A tiny class.\nclass Tiny\n  LIMIT = 3\nend\n", gem_name: 'tiny', gem_version: '0.1.0')
    end

    let(:source) { "Tiny\nTiny::LIMIT\n" }

    it 'says which gem a class comes from, before its documentation' do
      assert_equal("```ruby\nclass Tiny\n```\n\nFrom gem `tiny 0.1.0`\n\nA tiny class.", hover(0, 1))
    end

    it 'says which gem a constant comes from' do
      assert_equal("```ruby\nLIMIT\n```\n\nDefined in `Tiny`, line 3\n\nFrom gem `tiny 0.1.0`", hover(1, 8))
    end

    it 'says nothing about gems for a project definition' do
      project_manager.update_document_content('mine_uri', "class Mine\nend\nMine\n")
      project_manager.tags_for_uri('mine_uri')
      value = project_manager.hover_at('mine_uri', OpenStruct.new(line: 2, character: 1))&.dig(:contents, :value)
      assert_equal("```ruby\nclass Mine\n```", value)
    end
  end
end
