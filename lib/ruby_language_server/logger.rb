require 'logger'

module RubyLanguageServer
  level_name = ENV.fetch('LOG_LEVEL'){ 'info' }.upcase
  level = Logger::Severity.const_get(level_name)
  @logger = ::Logger.new(STDERR, level: level)
  def RubyLanguageServer.logger
    @logger
  end
end
