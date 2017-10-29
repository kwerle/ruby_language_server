require 'logger'

module RubyLanguageServer
  @logger = ::Logger.new(STDERR, ENV.fetch('LOG_LEVEL'){ 'debug' })
  def RubyLanguageServer.logger
    @logger
  end
end
