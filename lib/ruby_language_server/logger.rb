# frozen_string_literal: true

require 'logger'

module RubyLanguageServer
  level_name = ENV.fetch('LOG_LEVEL', 'error').upcase
  # level_name = 'DEBUG'
  level = Logger::Severity.const_get(level_name)
  class << self
    attr_accessor :logger
  end
  @logger = ::Logger.new($stderr, level: level)
  @logger.log(level, "Logger started at level #{level_name} -> #{level}")
end
