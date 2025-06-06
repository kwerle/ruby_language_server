# frozen_string_literal: true

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: '/database',
  pool: 5,
  timeout: 30.seconds # does not seem to help
)

ActiveSupport.on_load(:active_record) do
  database = ActiveRecord::Base.connection.raw_connection
  database.enable_load_extension(1)
  if Gem.win_platform?
    # load DLL from PATH
    database.load_extension('liblevenshtein.dll')
  else
    database.load_extension('/usr/local/lib/liblevenshtein.so.0.0.0')
  end
  database.enable_load_extension(0)
end

if ENV['LOG_LEVEL'] == 'DEBUG'
  begin
    warn('Turning on active record logging to active_record.log')
    ActiveRecord::Base.logger = Logger.new(File.open('/active_record.log', 'w'))
  rescue Exception => e
    ActiveRecord::Base.logger = Logger.new($stderr)
    ActiveRecord::Base.logger.error(e)
  end
end
