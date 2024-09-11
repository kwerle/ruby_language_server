# frozen_string_literal: true

require 'json'

module RubyLanguageServer
  class IO
    def initialize(server, mutex)
      @server = server
      @mutex = mutex
      server.io = self
      loop do
        (id, response) = process_request($stdin)
        return_response(id, response, $stdout) unless id.nil?
      rescue SignalException => e
        RubyLanguageServer.logger.error "We received a signal.  Let's bail: #{e}"
        exit
      rescue Exception => e
        RubyLanguageServer.logger.error "Something when horribly wrong: #{e}"
        backtrace = e.backtrace * "\n"
        RubyLanguageServer.logger.error "Backtrace:\n#{backtrace}"
      end
    end

    def return_response(id, response, io = $stdout)
      full_response = {
        jsonrpc: '2.0',
        id:,
        result: response
      }
      response_body = JSON.unparse(full_response)
      RubyLanguageServer.logger.info "return_response body: #{response_body}"
      io.write "Content-Length: #{response_body.length + 0}\r\n"
      io.write "\r\n"
      io.write response_body
      io.flush
    end

    def send_notification(message, params, io = $stdout)
      full_response = {
        jsonrpc: '2.0',
        method: message,
        params:
      }
      body = JSON.unparse(full_response)
      RubyLanguageServer.logger.info "send_notification body: #{body}"
      io.write "Content-Length: #{body.length + 0}\r\n"
      io.write "\r\n"
      io.write body
      io.flush
    end

    def process_request(io = $stdin)
      request_body = get_request(io)
      # RubyLanguageServer.logger.debug "request_body: #{request_body}"
      request_json = JSON.parse request_body
      id = request_json['id']
      method_name = request_json['method']
      params = request_json['params']
      method_name = "on_#{method_name.gsub(/[^\w]/, '_')}"
      if @server.respond_to? method_name
        response = ActiveRecord::Base.connection_pool.with_connection do
          retries = 3
          begin
            @server.send(method_name, params)
          rescue StandardError => e
            RubyLanguageServer.logger.warn("Error updating: #{e}\n#{e.backtrace * "\n"}")
            sleep 5
            retries -= 1
            retry unless retries <= 0
          end
        end
        exit if response == 'EXIT'
        [id, response]
      else
        RubyLanguageServer.logger.warn "SERVER DOES NOT RESPOND TO #{method_name}"
        nil
      end
    end

    def get_request(io = $stdin)
      initial_line = get_initial_request_line(io)
      RubyLanguageServer.logger.debug "initial_line: #{initial_line}"
      length = get_length(initial_line)
      content = ''
      while content.length < length + 2
        begin
          content += get_content(length + 2, io) # Why + 2?  CRLF?
        rescue Exception => e
          RubyLanguageServer.logger.error e
          # We have almost certainly been disconnected from the server
          exit!(1)
        end
      end
      RubyLanguageServer.logger.debug "content.length: #{content.length}"
      content
    end

    def get_initial_request_line(io = $stdin)
      io.gets
    end

    def get_length(string)
      return 0 if string.nil?

      string.match(/Content-Length: (\d+)/)[1].to_i
    end

    def get_content(size, io = $stdin)
      io.read(size)
    end

    # http://www.alecjacobson.com/weblog/?p=75
    # def stdin_read_char
    #   begin
    #     # save previous state of stty
    #     old_state = `stty -g`
    #     # disable echoing and enable raw (not having to press enter)
    #     system "stty raw -echo"
    #     c = STDIN.getc.chr
    #     # gather next two characters of special keys
    #     if(c=="\e")
    #       extra_thread = Thread.new{
    #         c = c + STDIN.getc.chr
    #         c = c + STDIN.getc.chr
    #       }
    #       # wait just long enough for special keys to get swallowed
    #       extra_thread.join(0.00001)
    #       # kill thread so not-so-long special keys don't wait on getc
    #       extra_thread.kill
    #     end
    #   rescue Exception => ex
    #     puts "#{ex.class}: #{ex.message}"
    #     puts ex.backtrace
    #   ensure
    #     # restore previous state of stty
    #     system "stty #{old_state}"
    #   end
    #   return c
    # end
  end # class
end # module
