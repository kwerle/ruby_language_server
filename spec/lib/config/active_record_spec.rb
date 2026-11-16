# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'

describe 'ActiveRecord initializer' do
  it 'keeps the database in the data directory' do
    data_dir = ENV.fetch('RUBY_LANGUAGE_SERVER_DATA_DIR', '/data')
    database = ActiveRecord::Base.connection_db_config.database

    assert_equal File.join(data_dir, 'database'), database
    refute_equal '/database', database
  end

  it 'waits 5 seconds for a database lock' do
    # The adapter reads :timeout as milliseconds. It used to be 30.seconds, which is 30 ms.
    assert_equal 5000, ActiveRecord::Base.connection_db_config.configuration_hash[:timeout]
  end
end
