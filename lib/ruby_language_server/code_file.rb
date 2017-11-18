require_relative 'scope_data/base'
require_relative 'scope_data/scope'
require_relative 'scope_data/variable'

module RubyLanguageServer

  class CodeFile

    attr_reader :uri
    attr :text
    attr_reader :lint_found

    def initialize(uri, text)
      RubyLanguageServer.logger.debug(@root_scope)
      @uri = uri
      @text = text
      # diagnostics
    end

    def text=(new_text)
      @text = new_text
      @root_scope = nil
    end

    def diagnostics
      # Maybe we should be sharing this GoodCop across instances
      @good_cop ||= GoodCop.new()
      cop_out = @good_cop.diagnostics(@text)
    end

    def root_scope
      @root_scope ||= ScopeParser.new(text).root_scope
    end

  end

end
