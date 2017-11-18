module RubyLanguageServer
  module Location

    def self.hash(uri, start_line, start_character = 1, end_line = nil, end_character = nil)
      {
        uri: uri,
        range: position_hash(start_line, start_character, end_line, end_character)
      }
    end

    def self.position_hash(start_line, start_character = 1, end_line = nil, end_character = nil)
      end_line = end_line || start_line
      end_character = end_character || start_character
      {
        start:
        {
          line: start_line - 1,
          character: start_character
        },
        :'end' =>
        {
          line: end_line - 1,
          character: end_character
        }
      }
    end

  end
end
