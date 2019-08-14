# frozen_string_literal: true

require 'pry'
require 'minitest/color'
require_relative '../lib/ruby_language_server'

module DatabaseClearing
  def setup
    super
    RubyLanguageServer::ScopeData::Scope.destroy_all
    RubyLanguageServer::ScopeData::Variable.destroy_all
    RubyLanguageServer::CodeFile.destroy_all
  end
end

Minitest::Test.prepend(DatabaseClearing)
