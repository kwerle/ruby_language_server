# frozen_string_literal: true

if ENV['COVERAGE']
  require 'simplecov'
  require 'simplecov_json_formatter'
  SimpleCov.start do
    add_filter '/spec/'
    add_filter '/vendor/'
    # Use JSON formatter for CI/Codecov integration
    formatter SimpleCov::Formatter::JSONFormatter if ENV['CI']
  end
end

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
