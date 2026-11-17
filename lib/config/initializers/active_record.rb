# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

# Everything the server writes goes in one directory, so the container can run with
# --read-only --tmpfs /data:uid=1000,gid=1000. Outside the image, where /data usually
# doesn't exist, use a temporary directory that is removed on exit.
data_dir = ENV.fetch('RUBY_LANGUAGE_SERVER_DATA_DIR') do
  if File.directory?('/data') && File.writable?('/data')
    '/data'
  else
    dir = Dir.mktmpdir('ruby_language_server')
    owner = Process.pid
    at_exit { FileUtils.remove_entry(dir, true) if Process.pid == owner } # not in the forked scanner
    dir
  end
end

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: File.join(data_dir, 'database'),
  pool: 5,
  timeout: 5000 # milliseconds SQLite waits for a lock held by the background scanner
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
