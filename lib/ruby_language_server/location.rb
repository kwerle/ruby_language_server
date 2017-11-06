module RubyLanguageServer
  module Location

    def self.hash(uri, start_line, start_character = 1, end_line = nil, end_character = nil)
        _end_line = end_line || start_line
        _end_character = end_character || start_character
        {
          uri: uri,
          range: {
            start: {
              line: start_line - 1,
              character: start_character
            },
          end: {
            line: _end_line - 1,
            character: _end_character
          }
        }
      }
    end

  end
end
