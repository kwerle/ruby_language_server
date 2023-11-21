# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'

describe Schema do
  describe '.already_initialized' do
    it 'is true' do
      assert(Schema.already_initialized)
    end
  end
end
