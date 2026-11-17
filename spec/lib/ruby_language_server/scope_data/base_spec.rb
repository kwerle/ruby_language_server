# frozen_string_literal: true

require_relative '../../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::ScopeData::Base do
  describe '.closest_to' do
    before do
      RubyLanguageServer::ScopeParser.new(<<~RUBY)
        class Widget
          def wiggle; end
          def waggle; end
          def it_s; end
        end
      RUBY
    end

    let(:scopes) { RubyLanguageServer::ScopeData::Scope }

    it 'orders by distance from the word' do
      assert_equal(%w[wiggle waggle], scopes.where(class_type: 'method').closest_to('wig').limit(2).map(&:name))
    end

    it 'skips names shorter than the word' do
      assert_equal([], scopes.where(name: 'it_s').closest_to('it_s_long').to_a)
    end

    it 'treats quotes and SQL in the word as data' do
      ["it's", "x') OR 1=1 --", "'; DROP TABLE scopes; --"].each do |word|
        assert_kind_of(Array, scopes.closest_to(word).to_a, word)
      end
      assert_equal(4, scopes.where.not(class_type: 'root').count)
    end
  end
end
