# frozen_string_literal: true

if ENV['COVERAGE']
  require 'simplecov'
  if ENV['CI']
    require 'simplecov_json_formatter'
    SimpleCov.formatter = SimpleCov::Formatter::JSONFormatter
  end
  SimpleCov.start do
    add_filter '/spec/'
    add_filter '/vendor/'
  end
end

# Re-parse on every request, so specs see each edit right away. The debounce specs set
# their own interval.
ENV['RUBY_LANGUAGE_SERVER_REPARSE_INTERVAL'] ||= '0'

require 'debug'
require 'ostruct'
require_relative '../lib/ruby_language_server'

require 'minitest/reporters'
Minitest::Reporters.use!

module DatabaseClearing
  def setup
    super
    RubyLanguageServer::ScopeData::Scope.destroy_all
    RubyLanguageServer::ScopeData::Variable.destroy_all
    RubyLanguageServer::CodeFile.destroy_all
  end
end

Minitest::Test.prepend(DatabaseClearing)
RubyLanguageServer.logger = Logger.new(File.open('test.log', 'w'))
