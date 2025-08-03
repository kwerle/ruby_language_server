# frozen_string_literal: true

require 'json'
require 'socket'

module RubyLanguageServer
  class IO
    attr_reader :using_socket

    def initialize(server, mutex)
      @server = server
      @mutex = mutex
      server.io = self

      configure_io

      loop do
        (id, response) = process_request(@in)
        return_response(id, response, @out) unless id.nil?
      rescue SignalException => e
        RubyLanguageServer.logger.error "We received a signal.  Let's bail: #{e}"
        exit
      rescue Exception => e
        RubyLanguageServer.logger.error "Something when horribly wrong: #{e}"
        backtrace = e.backtrace * "\n"
        RubyLanguageServer.logger.error "Backtrace:\n#{backtrace}"
      if @using_socket && @in
        begin
          @in.close
        rescue
        end
      end
    end

    private

    attr_accessor :in, :out

    def configure_io
      if ENV['LSP_PORT']
        @tcp_server = TCPServer.new(ENV['LSP_PORT'].to_i)
        RubyLanguageServer.logger.info "Listening on TCP port #{ENV['LSP_PORT']} for LSP connections"
        self.in = @tcp_server.accept
        self.out = self.in
        @using_socket = true
        RubyLanguageServer.logger.info "Accepted LSP socket connection"
      else
        self.in = $stdin
        self.out = $stdout
        @using_socket = false
      end
    end
    end

    def return_response(id, response, io = nil)
      io ||= out
      full_response = {
        jsonrpc: '2.0',
        id:,
        result: response
      }
      response_body = JSON.unparse(full_response)
      RubyLanguageServer.logger.info "return_response body: #{response_body}"
      io.write "Content-Length: #{response_body.length}\r\n"
      io.write "\r\n"
      io.write response_body
      io.flush if io.respond_to?(:flush)
    end

    def send_notification(message, params, io = nil)
      io ||= out
      full_response = {
        jsonrpc: '2.0',
        method: message,
        params:
      }
      body = JSON.unparse(full_response)
      RubyLanguageServer.logger.info "send_notification body: #{body}"
      io.write "Content-Length: #{body.length}\r\n"
      io.write "\r\n"
      io.write body
      io.flush if io.respond_to?(:flush)
    end

    def process_request(io = nil)
      io ||= self.in
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

    def get_request(io = nil)
      io ||= self.in
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

    def get_initial_request_line(io = nil)
      io ||= self.in
      io.gets
    end

    def get_length(string)
      return 0 if string.nil?
      string.match(/Content-Length: (\d+)/)[1].to_i
    end

    def get_content(size, io = nil)
      io ||= self.in
      io.read(size)
    end
  end # class
end # module
