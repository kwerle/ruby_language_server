require_relative 'scope_data/base'
require_relative 'scope_data/scope'
require_relative 'scope_data/variable'

module RubyLanguageServer

  class CodeFile

    # class Constant
    #   attr_accessor :line            # line
    #   attr_accessor :name            # name
    #   attr_accessor :full_name       # Module::Class::Name
    # end

    attr :text

    def initialize(text)
      RubyLanguageServer.logger.debug(@root_scope)
      @text = text
    end

    def text=(new_text)
      @text = new_text
      @root_scope = nil
    end

    def root_scope
      @root_scope ||= ScopeParser.new(text).root_scope
    end

  end

end
