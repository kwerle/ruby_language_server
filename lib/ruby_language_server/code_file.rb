require_relative 'scope_data/base'
require_relative 'scope_data/scope'
require_relative 'scope_data/variable'

module RubyLanguageServer

  class CodeFile
    attr_reader :uri
    attr_accessor :text
    attr_reader :lint_found
    attr_reader :tags

    def initialize(uri, text)
      RubyLanguageServer.logger.debug("CodeFile initialize #{uri}")
      @uri = uri
      @text = text
    end

    def text=(new_text)
      RubyLanguageServer.logger.debug("text= for #{uri}")
      if @text == new_text
        RubyLanguageServer.logger.debug("IT WAS THE SAME!!!!!!!!!!!!")
        return
      end
      @text = new_text
      @tags = nil
    end

    SymbolKind = {
      file: 1,
      :'module' => 5, #2,
      namespace: 3,
      package: 4,
      :'class' => 5,
      :'method' => 6,
      :'singleton method' => 6,
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
      array: 18,
    }

    def tags
      return @tags if !!@tags&.first
      RubyLanguageServer.logger.debug("Asking about tags for #{uri}")
      return {} if text.nil?
      RubyLanguageServer.logger.debug("Getting tags for #{uri}")
      ripper_tags = RipperTags::Parser.extract(text)
      # RubyLanguageServer.logger.error("ripper_tags: #{ripper_tags}")
      # Don't freak out and nuke the outline just because we're in the middle of typing a line and you can't parse the file.
      return @tags if !!@tags&.first && ripper_tags&.first.nil?

      tags = ripper_tags.map{ |reference|
        name = reference[:name] || 'undefined?'
        kind = SymbolKind[reference[:kind].to_sym] || 7
        kind = 9 if name == 'initialize' # Magical special case
        return_hash = {
          name: name,
          kind: kind,
          location: Location.hash(uri, reference[:line])
        }
        container_name = reference[:full_name].split(/(:{2}|\#|\.)/).compact[-3]
        return_hash[:containerName] = container_name if container_name
        return_hash
      }
      @tags = tags.reverse.each do |tag|
        child_tags = tags.select{ |child_tag| child_tag[:containerName] == tag[:name]}
        max_line = child_tags.map{ |child_tag| child_tag[:location][:range][:end][:line].to_i }.max || 0
        tag[:location][:range][:end][:line] = [tag[:location][:range][:end][:line], max_line].max
      end
      RubyLanguageServer.logger.debug("Done with tags for #{uri}: #{@tags}")
      # RubyLanguageServer.logger.debug("tags caller #{caller * ','}")
      @tags
    end

    def diagnostics
      # Maybe we should be sharing this GoodCop across instances
      @good_cop ||= GoodCop.new()
      cop_out = @good_cop.diagnostics(@text)
    end

    def root_scope
      RubyLanguageServer.logger.debug("Asking about root_scope")
      @root_scope ||= ScopeParser.new(text).root_scope
    end

  end

end
