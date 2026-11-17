# frozen_string_literal: true

# The purpose of this class is to parse a single line and return an array of the
# context words given the position of the cursor.

# FooModule::BarModule.method_name.ivar = some_var.some_method
#                        ^
# ['FooModule', 'BarModule', 'method_name']
#                                             ^
# ['some_var']

# If the first part of the context is :: then it returns a leading nil in the array

# ::FooModule
#     ^
# [nil, 'FooModule']

module RubyLanguageServer
  module LineContext
    # LSP Position.character counts UTF-16 code units - NOT UTF-8.
    # Returns the matching index into the
    # Ruby string, which counts characters. They differ for characters outside the BMP,
    # such as emoji, which take two code units.
    def self.character_index(line, utf16_offset)
      units = 0
      line.each_char.with_index do |char, index|
        return index if units >= utf16_offset

        units += char.ord > 0xFFFF ? 2 : 1
      end
      line.length
    end

    # This will not work if the search starts on the ending ? of "method?".  Bummer.
    def self.for(line, position)
      # Grab just the last part of the line - from the index onward
      line_end = line[position..]
      return nil if line_end.nil?

      # Grab the portion of the word that starts at the position toward the end of the line
      match = line_end.partition(/^(@{0,2}\w+\??)/)[1]
      RubyLanguageServer.logger.debug("match: #{match}")
      # Get the start of the line to the end of the matched word
      line_start = line[0..(position + match.length - 1)]
      RubyLanguageServer.logger.debug("line_start: #{line_start}")
      # Match as much as we can to the end of the line - which is now the end of the word
      end_match = line_start.partition(/(@{0,2}[:&.\w]+\??)$/)[1]
      matches = end_match.split('&.', -1)
      matches = matches.map { |m| m.length.positive? ? m.split('.', -1) : m }.flatten
      matches = matches.map { |m| m.length.positive? ? m.split('::', -1) : m }.flatten
      RubyLanguageServer.logger.debug("matches: #{matches}")
      matches
    end
  end
end
