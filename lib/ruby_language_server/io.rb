require 'json'

module RubyLanguageServer
  class IO

    def initialize(server)
      RubyLanguageServer.logger.level = Logger::INFO
      @server = server
      while true do
        begin
          (id, response) = process_request(STDIN)
          return_response(id, response, STDOUT) unless id.nil?
        rescue SignalException => e
          RubyLanguageServer.logger.error "We received a signal.  Let's bail: #{e}"
          exit(true)
        rescue Exception => e
          RubyLanguageServer.logger.error "Something when horribly wrong: #{e}"
          backtrace = e.backtrace * "\n"
          RubyLanguageServer.logger.error "Backtrace:\n#{backtrace}"
        end
      end
    end

    def return_response(id, response, io=STDOUT)
      full_response = {
        jsonrpc: '2.0',
        id: id,
        result: response
      }
      response_body = JSON.unparse(full_response)
      RubyLanguageServer.logger.debug "response_body: #{response_body}"
      io.write "Content-Length: #{response_body.length + 0}\r\n"
      io.write "\r\n"
      io.write response_body
      io.flush
    end

    def process_request(io = STDIN)
      request_body = get_request(io)
      RubyLanguageServer.logger.debug "request_body: #{request_body}"
      request_json = JSON.parse request_body
      RubyLanguageServer.logger.debug "request_body: #{request_body}"
      id = request_json['id']
      method_name = request_json['method']
      params = request_json['params']
      method_name = "on_#{method_name.gsub(/[^\w]/, '_')}"
      if @server.respond_to? method_name
        response = @server.send(method_name, params)
        if response == "EXIT"
          exit(true)
        end
        return id, response
      else
        RubyLanguageServer.logger.warn "SERVER DOES NOT RESPOND TO #{method_name}"
        return nil
      end
    end

    def get_request(io = STDIN)
      initial_line = get_initial_request_line(io)
      RubyLanguageServer.logger.debug "initial_line: #{initial_line}"
      length = get_length(initial_line)
      content = ''
      while content.length < length + 2 do
        content << get_content(length + 2, io) # Why + 2?  CRLF?
      end
      RubyLanguageServer.logger.debug "content.length: #{content.length}"
      content
    end

    def get_initial_request_line(io = STDIN)
      gets
    end

    def get_length(string)
      string.match(/Content-Length: (\d+)/)[1].to_i
    end

    def get_content(size, io = STDIN)
      io.read(size)
    end

    # http://www.alecjacobson.com/weblog/?p=75
    def stdin_read_char
      begin
        # save previous state of stty
        old_state = `stty -g`
        # disable echoing and enable raw (not having to press enter)
        system "stty raw -echo"
        c = STDIN.getc.chr
        # gather next two characters of special keys
        if(c=="\e")
          extra_thread = Thread.new{
            c = c + STDIN.getc.chr
            c = c + STDIN.getc.chr
          }
          # wait just long enough for special keys to get swallowed
          extra_thread.join(0.00001)
          # kill thread so not-so-long special keys don't wait on getc
          extra_thread.kill
        end
      rescue => ex
        puts "#{ex.class}: #{ex.message}"
        puts ex.backtrace
      ensure
        # restore previous state of stty
        system "stty #{old_state}"
      end
      return c
    end

  end # class
end # module
