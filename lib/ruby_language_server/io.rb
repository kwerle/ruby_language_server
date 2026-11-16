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
        (id, response) = process_request
        return_response(id, response) unless id.nil?
      rescue SignalException => e
        RubyLanguageServer.logger.error "We received a signal.  Let's bail: #{e}"
        exit
      rescue Exception => e
        RubyLanguageServer.logger.error "Something when horribly wrong: #{e}"
        backtrace = e.backtrace * "\n"
        RubyLanguageServer.logger.error "Backtrace:\n#{backtrace}"
      end
      return unless @using_socket

      begin
        @in&.close
      rescue StandardError => e
        RubyLanguageServer.logger.error "Error closing socket: #{e}"
      end
    end

    # JSON-RPC error code for a request whose method the server doesn't implement.
    METHOD_NOT_FOUND = -32_601

    def send_notification(message, params)
      body = write_message(jsonrpc: '2.0', method: message, params:)
      RubyLanguageServer.logger.info "send_notification body: #{body}"
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
        RubyLanguageServer.logger.info 'Accepted LSP socket connection'
      else
        self.in = $stdin
        # Keep the real stdout for protocol messages and send anything else written to
        # $stdout (a stray puts, a gem warning) to stderr, so it can't corrupt the stream.
        self.out = $stdout.dup
        out.binmode
        $stdout.reopen($stderr)
        @using_socket = false
      end
    end

    def return_response(id, response)
      body = write_message(jsonrpc: '2.0', id:, result: response)
      RubyLanguageServer.logger.info "return_response body: #{body}"
    end

    def return_error(id, code, message)
      body = write_message(jsonrpc: '2.0', id:, error: { code:, message: })
      RubyLanguageServer.logger.info "return_error body: #{body}"
    end

    # Writes one framed LSP message and returns its JSON body.
    # Content-Length is a byte count, not a character count.
    def write_message(message)
      body = JSON.generate(message)
      out.write "Content-Length: #{body.bytesize}\r\n"
      out.write "\r\n"
      out.write body
      out.flush if out.respond_to?(:flush)
      body
    end

    def process_request
      request_body = get_request
      # RubyLanguageServer.logger.debug "request_body: #{request_body}"
      request_json = JSON.parse request_body
      id = request_json['id']
      lsp_method = request_json['method']
      params = request_json['params']
      method_name = "on_#{lsp_method.gsub(/[^\w]/, '_')}"
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
        # Every request needs a reply, or the client waits forever. Notifications get none.
        return_error(id, METHOD_NOT_FOUND, "Method not found: #{lsp_method}") unless id.nil?
        nil
      end
    end

    def get_request # rubocop:disable Naming/AccessorMethodName
      initial_line = get_initial_request_line
      RubyLanguageServer.logger.debug "initial_line: #{initial_line}"
      length = get_length(initial_line)
      content = ''
      while content.length < length + 2
        begin
          content += get_content(length + 2) # Why + 2?  CRLF?
        rescue Exception => e
          RubyLanguageServer.logger.error e
          # We have almost certainly been disconnected from the server
          exit!(1)
        end
      end
      RubyLanguageServer.logger.debug "content.length: #{content.length}"
      content
    end

    def get_initial_request_line # rubocop:disable Naming/AccessorMethodName
      self.in.gets
    end

    def get_length(string)
      return 0 if string.nil?

      string.match(/Content-Length: (\d+)/)[1].to_i
    end

    def get_content(size)
      self.in.read(size)
    end
  end # class
end # module
