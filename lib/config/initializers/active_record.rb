# frozen_string_literal: true

extension_path = if Gem.win_platform?
                   'liblevenshtein.dll'
                 else
                   '/usr/local/lib/liblevenshtein.so.0.0.0'
                 end

# Everything the server writes goes in one directory, so the container can run with
# --read-only --tmpfs /data:uid=1000,gid=1000.
data_dir = ENV.fetch('RUBY_LANGUAGE_SERVER_DATA_DIR', '/data')

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: File.join(data_dir, 'database'),
  pool: 5,
  timeout: 30.seconds, # does not seem to help
  extensions: [extension_path]
)

if ENV['LOG_LEVEL'] == 'DEBUG'
  begin
    log_path = File.join(data_dir, 'active_record.log')
    warn("Turning on active record logging to #{log_path}")
    ActiveRecord::Base.logger = Logger.new(File.open(log_path, 'w'))
  rescue Exception => e
    ActiveRecord::Base.logger = Logger.new($stderr)
    ActiveRecord::Base.logger.error(e)
  end
end
