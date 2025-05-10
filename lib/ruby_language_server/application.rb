# frozen_string_literal: true

require 'active_record'

require_relative 'logger' # do this first!
require_relative '../config/initializers/sqlite'
require_relative '../config/initializers/active_record'
require_relative '../db/schema'

require_relative 'version'
require_relative 'gem_installer'
require_relative 'io'
require_relative 'location'
require_relative 'code_file'
require_relative 'scope_parser'
require_relative 'project_manager'
require_relative 'server'
require_relative 'line_context'
require_relative 'completion'

module RubyLanguageServer
  class Application
    def start
      update_mutex = Monitor.new
      server = RubyLanguageServer::Server.new(update_mutex)
      RubyLanguageServer::IO.new(server, update_mutex)
    end
  end
end
