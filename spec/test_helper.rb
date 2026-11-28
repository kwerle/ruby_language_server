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
# The project scan forks and would store all of Ruby core in the shared test database while
# other specs run. Specs that want core call CoreIndex.load!(only: ...) themselves.
ENV['RUBY_LANGUAGE_SERVER_CORE_INDEX'] ||= 'false'
# Nor should it download and store the gems in the project's Gemfile.lock.
ENV['RUBY_LANGUAGE_SERVER_GEM_INDEX'] ||= 'false'

require 'debug'
require 'ostruct'
require_relative '../lib/ruby_language_server'

require 'minitest/reporters'
Minitest::Reporters.use!

module DatabaseClearing
  def setup
    super
    # delete_all, not destroy_all: every table is emptied, so there's nothing for callbacks
    # to do, and destroying thousands of Ruby core scopes (CoreIndex) one by one is slow.
    RubyLanguageServer::ScopeData::Scope.delete_all
    RubyLanguageServer::ScopeData::Variable.delete_all
    RubyLanguageServer::CodeFile.delete_all
  end
end

Minitest::Test.prepend(DatabaseClearing)
RubyLanguageServer.logger = Logger.new(File.open('test.log', 'w'))
