# frozen_string_literal: true

# Set up a database that resides in RAM
ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: 'file::memory:?cache=shared'
)

if ENV['LOG_LEVEL'] == 'DEBUG'
  begin
    warn('Turning on active record logging')
    ActiveRecord::Base.logger = Logger.new(File.open('active_record.log', 'w'))
  rescue Exception => e
    ActiveRecord::Base.logger = Logger.new(STDERR)
    ActiveRecord::Base.logger.error(e)
  end
end
