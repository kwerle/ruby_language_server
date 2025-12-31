# frozen_string_literal: true

extension_path = if Gem.win_platform?
                   'liblevenshtein.dll'
                 else
                   '/usr/local/lib/liblevenshtein.so.0.0.0'
                 end

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: '/database',
  pool: 5,
  timeout: 30.seconds, # does not seem to help
  extensions: [extension_path]
)

if ENV['LOG_LEVEL'] == 'DEBUG'
  begin
    warn('Turning on active record logging to active_record.log')
    ActiveRecord::Base.logger = Logger.new(File.open('/active_record.log', 'w'))
  rescue Exception => e
    ActiveRecord::Base.logger = Logger.new($stderr)
    ActiveRecord::Base.logger.error(e)
  end
end
