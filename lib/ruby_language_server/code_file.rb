# frozen_string_literal: true

require_relative 'scope_data/base'
require_relative 'scope_data/scope'
require_relative 'scope_data/variable'

module RubyLanguageServer
  class CodeFile
    attr_reader :uri
    attr_reader :text
    attr_reader :lint_found

    def initialize(uri, text)
      RubyLanguageServer.logger.debug("CodeFile initialize #{uri}")
      @uri = uri
      @text = text
      @refresh_root_scope = true
    end

    def text=(new_text)
      RubyLanguageServer.logger.debug("text= for #{uri}")
      if @text == new_text
        RubyLanguageServer.logger.debug('IT WAS THE SAME!!!!!!!!!!!!')
        return
      end
      @text = new_text
      @refresh_root_scope = true
    end

    SYMBOL_KIND = {
      file: 1,
      'module': 5, # 2,
      namespace: 3,
      package: 4,
      'class': 5,
      'method': 6,
      'singleton method': 6,
      property: 7,
      field: 8,
      constructor: 9,
      enum: 10,
      interface: 11,
      function: 12,
      variable: 13,
      constant: 14,
      string: 15,
      number: 16,
      boolean: 17,
      array: 18
    }.freeze

    # Find the ancestor of this scope with a name and return that.  Or nil.
    def ancestor_scope_name(scope)
      return_scope = scope
      while (return_scope = return_scope.parent)
        return return_scope.name unless return_scope.name.nil?
      end
    end

    def tags
      RubyLanguageServer.logger.debug("Asking about tags for #{uri}")
      return @tags = {} if text.nil? || text == ''

      tags = []
      root_scope.self_and_descendants.each do |scope|
        next if scope.type == ScopeData::Base::TYPE_BLOCK

        name = scope.name
        kind = SYMBOL_KIND[scope.type] || 7
        kind = 9 if name == 'initialize' # Magical special case
        scope_hash = {
          name: name,
          kind: kind,
          location: Location.hash(uri, scope.top_line)
        }
        container_name = ancestor_scope_name(scope)
        scope_hash[:containerName] = container_name if container_name
        tags << scope_hash

        scope.variables.each do |variable|
          name = variable.name
          # We only care about counstants
          next unless name =~ /^[A-Z]/

          variable_hash = {
            name: name,
            kind: SYMBOL_KIND[:constant],
            location: Location.hash(uri, variable.line),
            container_name: scope.name
          }
          tags << variable_hash
        end
      end
      # byebug
      tags.reject! { |tag| tag[:name].nil? }
      # RubyLanguageServer.logger.debug("Raw tags for #{uri}: #{tags}")
      @tags = tags.reverse_each do |tag|
        child_tags = tags.select { |child_tag| child_tag[:containerName] == tag[:name] }
        max_line = child_tags.map { |child_tag| child_tag[:location][:range][:end][:line].to_i }.max || 0
        tag[:location][:range][:end][:line] = [tag[:location][:range][:end][:line], max_line].max
      end
      # RubyLanguageServer.logger.debug("Done with tags for #{uri}: #{@tags}")
      # RubyLanguageServer.logger.debug("tags caller #{caller * ','}")
      @tags
    end

    def diagnostics
      # Maybe we should be sharing this GoodCop across instances
      @good_cop ||= GoodCop.new
      @good_cop.diagnostics(@text, @uri)
    end

    def root_scope
      # RubyLanguageServer.logger.error("Asking about root_scope with #{text}")
      if @refresh_root_scope
        new_root_scope = ScopeParser.new(text).root_scope
        @root_scope ||= new_root_scope # In case we had NONE
        return @root_scope if new_root_scope.children.empty?

        @root_scope = new_root_scope
        @refresh_root_scope = false
        @tags = nil
      end
      @root_scope
    end
  end
end
