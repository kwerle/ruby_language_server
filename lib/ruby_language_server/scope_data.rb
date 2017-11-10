require_relative 'scope_data/base'
require_relative 'scope_data/scope'
require_relative 'scope_data/variable'

module RubyLanguageServer

  class CodeFile

    class Constant
      attr_accessor :line            # line
      attr_accessor :name            # name
      attr_accessor :full_name       # Module::Class::Name
    end

    attr_reader :scopes

    def initialize(text)
      scope_parser = ScopeParser.sexp(text)
      RubyLanguageServer.logger.error(scope_parser)
    end

  end

end
