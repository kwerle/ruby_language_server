# frozen_string_literal: true

require 'byebug'
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
