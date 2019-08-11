# frozen_string_literal: true

# Set up a database that resides in RAM
ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: ':memory:'
)

if ENV['LOG_LEVEL'] == 'DEBUG'
  warn('Turning on active record logging')
  ActiveRecord::Base.logger = Logger.new(File.open('active_record.log', 'w'))
end
