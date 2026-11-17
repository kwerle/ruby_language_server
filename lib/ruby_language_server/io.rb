# frozen_string_literal: true

require 'json'
require 'socket'

module RubyLanguageServer
  class IO
    attr_reader :using_socket

    def initialize(server)
      @server = server
      server.io = self

      configure_io
      run_loop
      return unless @using_socket

      begin
        @in&.close
      rescue StandardError => e
        RubyLanguageServer.logger.error "Error closing socket: #{e}"
      end
    end

    # JSON-RPC error codes.
    INVALID_REQUEST = -32_600 # used for requests that arrive after shutdown
    METHOD_NOT_FOUND = -32_601
    INTERNAL_ERROR = -32_603 # used when a request handler raises

    # The background scanner (ProjectManager#scan_all_project_files) writes to the same SQLite
    # database. SQLite waits up to the connection's busy timeout for a lock; these cover the rare
    # BUSY it returns without waiting.
    BUSY_RETRIES = 2
    BUSY_RETRY_DELAY = 0.1 # seconds

    def send_notification(message, params)
      body = write_message(jsonrpc: '2.0', method: message, params:)
      RubyLanguageServer.logger.info "send_notification body: #{body}"
    end

    # Sends a request to the client and returns its id. The client's response is logged
    # and otherwise ignored (see #process_request).
    def send_request(message, params)
      @next_request_id = (@next_request_id || 0) + 1
      id = "ruby_language_server-#{@next_request_id}"
      body = write_message(jsonrpc: '2.0', id:, method: message, params:)
      RubyLanguageServer.logger.info "send_request body: #{body}"
      id
    end

    private

    attr_accessor :in, :out

    def run_loop
      loop do
        (id, response) = process_request
        return_response(id, response) unless id.nil?
      rescue SystemExit
        raise # on_exit, or a signal below. Don't treat it as an error and keep looping.
      rescue SignalException => e
        RubyLanguageServer.logger.error "We received a signal.  Let's bail: #{e}"
        exit
      rescue Exception => e
        RubyLanguageServer.logger.error "Something when horribly wrong: #{e}"
        backtrace = e.backtrace * "\n"
        RubyLanguageServer.logger.error "Backtrace:\n#{backtrace}"
      end
    end

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

    def log_client_response(response)
      if response['error']
        RubyLanguageServer.logger.warn "Client returned an error for request #{response['id']}: #{response['error']}"
      else
        RubyLanguageServer.logger.info "Client replied to request #{response['id']}"
      end
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
      request_body = read_request
      # RubyLanguageServer.logger.debug "request_body: #{request_body}"
      request_json = JSON.parse request_body
      id = request_json['id']
      lsp_method = request_json['method']
      params = request_json['params']
      if lsp_method.nil?
        # A response to a request we sent the client, such as client/registerCapability.
        log_client_response(request_json)
        return nil
      end
      method_name = "on_#{lsp_method.gsub(/[^\w]/, '_')}"
      if !id.nil? && @server.respond_to?(:shutdown_requested?) && @server.shutdown_requested?
        RubyLanguageServer.logger.warn "Request #{lsp_method} after shutdown"
        return_error(id, INVALID_REQUEST, "Server is shutting down; received #{lsp_method}")
        return nil
      end
      if @server.respond_to? method_name
        begin
          [id, call_handler(method_name, params)]
        rescue StandardError => e
          RubyLanguageServer.logger.error("Error in #{lsp_method}: #{e.class}: #{e.message}\n#{e.backtrace * "\n"}")
          # A request gets an error reply, so the client doesn't mistake it for an empty result.
          # Notifications get none.
          return_error(id, INTERNAL_ERROR, "#{e.class}: #{e.message}") unless id.nil?
          nil
        end
      else
        RubyLanguageServer.logger.warn "SERVER DOES NOT RESPOND TO #{method_name}"
        # Every request needs a reply, or the client waits forever. Notifications get none.
        return_error(id, METHOD_NOT_FOUND, "Method not found: #{lsp_method}") unless id.nil?
        nil
      end
    end

    # Calls the handler, retrying only when the database is locked.
    def call_handler(method_name, params)
      ActiveRecord::Base.connection_pool.with_connection do
        attempts = 0
        begin
          @server.send(method_name, params)
        rescue ActiveRecord::StatementTimeout => e
          attempts += 1
          raise if attempts > BUSY_RETRIES

          RubyLanguageServer.logger.warn("Database busy in #{method_name}, retrying: #{e.message}")
          sleep busy_retry_delay
          retry
        end
      end
    end

    def busy_retry_delay
      BUSY_RETRY_DELAY
    end

    # Reads one framed message: header lines up to the blank line that ends them, then
    # exactly Content-Length bytes of body. Exits if the client has disconnected.
    def read_request
      length = read_content_length
      content = read_content(length)
      if content.nil? || content.bytesize < length
        RubyLanguageServer.logger.error("Expected #{length} bytes, got #{content&.bytesize.to_i}; client disconnected")
        exit!(1)
      end
      RubyLanguageServer.logger.debug "content.bytesize: #{content.bytesize}"
      content
    end

    # Reads the header block and returns its Content-Length. Other headers, such as
    # Content-Type, are skipped. Header names are case-insensitive.
    def read_content_length
      length = nil
      headers_seen = false
      loop do
        line = read_header_line
        if line.nil?
          RubyLanguageServer.logger.error('End of input while reading headers; client disconnected')
          exit!(1)
        end
        line = line.chomp
        RubyLanguageServer.logger.debug "header: #{line}"
        # A blank line ends the headers. Tolerate stray blank lines before the first header.
        if line.empty?
          break if headers_seen

          next
        end
        headers_seen = true
        name, value = line.split(':', 2)
        length = Integer(value.strip, 10) if value && name.strip.casecmp?('Content-Length')
      end
      raise ArgumentError, 'Message has no Content-Length header' if length.nil?

      length
    end

    def read_header_line
      self.in.gets
    end

    def read_content(size)
      self.in.read(size)
    end
  end # class
end # module
