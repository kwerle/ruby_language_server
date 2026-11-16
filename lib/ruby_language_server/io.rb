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
