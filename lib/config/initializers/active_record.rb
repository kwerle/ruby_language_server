# Set up a database that resides in RAM
ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: ':memory:'
)

if ENV['LOG_LEVEL'] == 'DEBUG'
  STDERR.puts("Turning on active record logging")
  ActiveRecord::Base.logger = Logger.new(STDERR)
end
