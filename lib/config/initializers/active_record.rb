# frozen_string_literal: true

# Set up a database that resides in RAM
connection_pool = ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: 'file::memory:?cache=shared',
  pool: 5 # does not seem to help
)
connection_pool.checkout_timeout = 20 # does not seem to help

if ENV['LOG_LEVEL'] == 'DEBUG'
  begin
    warn('Turning on active record logging')
    ActiveRecord::Base.logger = Logger.new(File.open('active_record.log', 'w'))
  rescue Exception => e
    ActiveRecord::Base.logger = Logger.new(STDERR)
    ActiveRecord::Base.logger.error(e)
  end
end
