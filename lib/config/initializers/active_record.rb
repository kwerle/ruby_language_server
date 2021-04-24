# frozen_string_literal: true

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: 'file::memory:?cache=shared',
  # database: '/database',
  pool: 5, # does not seem to help
  checkout_timeout: 30.seconds # does not seem to help
)

database = ActiveRecord::Base.connection.instance_variable_get :@connection
database.enable_load_extension(1)
database.load_extension('/usr/local/lib/liblevenshtein.so.0.0.0')
database.enable_load_extension(0)

if ENV['LOG_LEVEL'] == 'DEBUG'
  begin
    warn('Turning on active record logging to active_record.log')
    ActiveRecord::Base.logger = Logger.new(File.open('active_record.log', 'w'))
  rescue Exception => e
    ActiveRecord::Base.logger = Logger.new($stderr)
    ActiveRecord::Base.logger.error(e)
  end
end
