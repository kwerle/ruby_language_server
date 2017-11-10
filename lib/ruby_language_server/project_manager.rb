require 'ripper-tags'

module RubyLanguageServer

  class ProjectManager

    def initialize(uri)
      # We don't seem to use this - but I'm emotionally attached.
      @root_path = uri
      # This is {uri: {content stuff}} where content stuff is like text: , tags: ...
      @file_tags = {}
    end

    def text_for_uri(uri)
      hash = @file_tags[uri]
      hash[:text] || ''
    end

    SymbolKind = {
      file: 1,
      :'module' => 5, #2,
      namespace: 3,
      package: 4,
      :'class' => 5,
      :'method' => 6,
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

    def tags_for_uri(uri)
      hash = @file_tags[uri] || []
      cop_tags = hash[:tags] || []
      cop_tags.map{ |reference|
        return_hash = {
          name: reference[:name] || 'undefined?',
          kind: SymbolKind[reference[:kind].to_sym] || 7,
          location: Location.hash(uri, reference[:line])
        }
        container_name = reference[:full_name].split(/(:{2}|\#)/).compact[-3]
        return_hash[:containerName] = container_name if container_name
        return_hash
      }
    end

    def update_document_content(uri, text)
      @file_tags[uri] = {text: text}
      CodeFile.new(text)
      tags = RipperTags::Parser.extract(text)
      # Don't freak out and nuke the outline just because we're in the middle of typing a line and you can't parse the file.
      unless (tags.nil? || tags == [])
        @file_tags[uri][:tags] = tags
      end
    end

    def possible_definitions_for(name)
      return {} if name == ''
      return_array = @file_tags.keys.inject([]) do |return_array, uri|
        tags = tags_for_uri(uri)
        match_tags = tags.select{|tag| tag[:name] == name}
        match_tags.each do |tag|
          return_array << Location.hash(uri, tag[:location][:range][:start][:line] + 1)
        end
        return_array
      end
      return_array
    end

  end
end
