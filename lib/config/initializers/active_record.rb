# frozen_string_literal: true

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: 'file::memory:?cache=shared',
  # database: '/database',
  pool: 5, # does not seem to help
  checkout_timeout: 30.seconds # does not seem to help
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
