# frozen_string_literal: true

require_relative '../../test_helper'
require 'stringio'
require 'json'
require 'tmpdir'

class TestRubyLanguageServerIO < Minitest::Test
  def setup
    @fake_in = StringIO.new
    @fake_out = StringIO.new
    @server = Object.new
    @mutex = Object.new
  end

  def test_initialize_sets_up_stdio_streams_and_assigns_server_io
    # Patch ENV to ensure stdio mode
    assert_nil ENV.fetch('LSP_PORT', nil)

    # Create a subclass that overrides initialization to avoid the infinite loop
    fake_in = @fake_in
    fake_out = @fake_out
    test_io_class = Class.new(RubyLanguageServer::IO) do
      define_method(:initialize) do |server, mutex|
        @server = server
        @mutex = mutex
        server.io = self
        # Call configure_io but skip the loop
        send(:in=, fake_in)
        send(:out=, fake_out)
        @using_socket = false
      end
    end

    server = Object.new
    server.define_singleton_method(:io=) { |val| @io = val }
    server.define_singleton_method(:io) { @io }

    # No need for a thread since we're not looping
    test_io_class.new(server, @mutex)

    assert_instance_of test_io_class, server.io
  end

  def test_return_response_writes_jsonrpc_response
    io = RubyLanguageServer::IO.allocate
    io.send(:out=, @fake_out)
    io.send(:return_response, 1, {foo: 'bar'})
    str = @fake_out.string
    assert_includes str, 'Content-Length:'
    assert_includes str, 'jsonrpc'
    assert_includes str, 'foo'
  end

  def test_send_notification_writes_jsonrpc_notification
    io = RubyLanguageServer::IO.allocate
    io.send(:out=, @fake_out)
    io.send(:send_notification, 'testMethod', {foo: 'bar'})
    str = @fake_out.string
    assert_includes str, 'Content-Length:'
    assert_includes str, 'testMethod'
    assert_includes str, 'foo'
  end

  def test_return_response_content_length_is_bytesize
    io = RubyLanguageServer::IO.allocate
    io.send(:out=, @fake_out)
    io.send(:return_response, 1, { name: 'Café ☕' })
    assert_content_length_matches_body_bytes(@fake_out.string, 'result')
  end

  def test_send_notification_content_length_is_bytesize
    io = RubyLanguageServer::IO.allocate
    io.send(:out=, @fake_out)
    io.send(:send_notification, 'testMethod', { name: 'Café ☕' })
    assert_content_length_matches_body_bytes(@fake_out.string, 'params')
  end

  def test_configure_io_stdio_redirects_stdout_to_stderr
    assert_nil ENV.fetch('LSP_PORT', nil)
    original_stdout = $stdout
    original_stderr = $stderr
    Dir.mktmpdir do |dir|
      stdout_path = File.join(dir, 'stdout')
      stderr_path = File.join(dir, 'stderr')
      $stdout = File.open(stdout_path, 'w')
      $stderr = File.open(stderr_path, 'w')
      io = RubyLanguageServer::IO.allocate
      io.send(:configure_io)
      out = io.send(:out)
      out.write 'protocol'
      out.flush
      $stdout.write 'stray'
      $stdout.flush

      assert out.binmode?
      assert_equal 'protocol', File.read(stdout_path)
      assert_equal 'stray', File.read(stderr_path)
    ensure
      out&.close
      $stdout.close unless $stdout == original_stdout
      $stderr.close unless $stderr == original_stderr
      $stdout = original_stdout
      $stderr = original_stderr
    end
  end

  def test_get_length_returns_correct_length
    io = RubyLanguageServer::IO.allocate
    assert_equal 42, io.send(:get_length, 'Content-Length: 42')
    assert_equal 0, io.send(:get_length, nil)
  end

  def test_get_initial_request_line_reads_line
    io = RubyLanguageServer::IO.allocate
    @fake_in.string = "Content-Length: 42\n"
    io.send(:in=, @fake_in)
    assert_equal "Content-Length: 42\n", io.send(:get_initial_request_line)
  end

  def test_get_content_reads_bytes
    io = RubyLanguageServer::IO.allocate
    @fake_in.string = 'abcdefg'
    io.send(:in=, @fake_in)
    assert_equal 'abc', io.send(:get_content, 3)
  end

  def test_get_request_reads_body
    io = RubyLanguageServer::IO.allocate
    header = "Content-Length: 5\n"
    body = "abcde\r\n"
    fake_in = StringIO.new(header + body)
    io.send(:in=, fake_in)
    assert_includes io.send(:get_request), 'abcde'
  end

  def test_process_request_calls_server_method_and_returns_response
    server = Object.new
    def server.on_test_method(params)
      { result: params['foo'] }
    end
    request = { id: 1, method: 'test_method', params: { 'foo' => 'bar' } }.to_json
    header = "Content-Length: #{request.bytesize}\n"
    body = "#{request}\r\n"
    fake_in = StringIO.new(header + body)
    io = RubyLanguageServer::IO.allocate
    io.send(:in=, fake_in)
    io.instance_variable_set(:@server, server)
    result = io.send(:process_request)
    assert_equal [1, { result: 'bar' }], result
  end

  def test_process_request_replies_method_not_found_for_unknown_request
    io = io_for_request({ jsonrpc: '2.0', id: 7, method: 'textDocument/references', params: {} })
    assert_nil io.send(:process_request)

    message = parse_written_message(@fake_out.string)
    assert_equal 7, message['id']
    assert_equal(-32_601, message['error']['code'])
    assert_includes message['error']['message'], 'textDocument/references'
    refute message.key?('result')
  end

  def test_process_request_ignores_unknown_notification
    io = io_for_request({ jsonrpc: '2.0', method: 'textDocument/didClose', params: {} })
    assert_nil io.send(:process_request)
    assert_equal '', @fake_out.string
  end

  def test_process_request_replies_internal_error_when_handler_raises
    server = counting_server { raise 'boom' }
    io = io_for_request({ jsonrpc: '2.0', id: 9, method: 'test_method', params: {} }, server)
    assert_nil io.send(:process_request)

    message = parse_written_message(@fake_out.string)
    assert_equal 9, message['id']
    assert_equal(-32_603, message['error']['code'])
    assert_includes message['error']['message'], 'RuntimeError: boom'
    refute message.key?('result')
    assert_equal 1, server.calls # not retried
  end

  def test_process_request_notification_that_raises_sends_nothing
    server = counting_server { raise 'boom' }
    io = io_for_request({ jsonrpc: '2.0', method: 'test_method', params: {} }, server)
    assert_nil io.send(:process_request)
    assert_equal '', @fake_out.string
  end

  def test_process_request_retries_busy_database_then_succeeds
    server = counting_server do |calls, _params|
      raise ActiveRecord::StatementTimeout, 'database is locked' if calls == 1

      'done'
    end
    io = io_for_request({ jsonrpc: '2.0', id: 3, method: 'test_method', params: {} }, server)
    assert_equal [3, 'done'], io.send(:process_request)
    assert_equal 2, server.calls
    assert_equal '', @fake_out.string
  end

  def test_process_request_busy_database_gives_up_with_internal_error
    server = counting_server { raise ActiveRecord::StatementTimeout, 'database is locked' }
    io = io_for_request({ jsonrpc: '2.0', id: 4, method: 'test_method', params: {} }, server)
    assert_nil io.send(:process_request)
    assert_equal RubyLanguageServer::IO::BUSY_RETRIES + 1, server.calls

    message = parse_written_message(@fake_out.string)
    assert_equal(-32_603, message['error']['code'])
    assert_includes message['error']['message'], 'ActiveRecord::StatementTimeout'
  end

  def test_return_error_writes_jsonrpc_error
    io = RubyLanguageServer::IO.allocate
    io.send(:out=, @fake_out)
    io.send(:return_error, 3, -32_601, 'Method not found: café')

    message = parse_written_message(@fake_out.string)
    assert_equal({ 'jsonrpc' => '2.0', 'id' => 3,
                   'error' => { 'code' => -32_601, 'message' => 'Method not found: café' } }, message)
  end

  def test_shutdown_then_exit_exits_zero
    io = io_for_session([{ jsonrpc: '2.0', id: 1, method: 'shutdown', params: nil },
                         { jsonrpc: '2.0', method: 'exit' }])
    error = assert_raises(SystemExit) { io.send(:run_loop) }

    assert_equal 0, error.status
    assert_equal [{ 'jsonrpc' => '2.0', 'id' => 1, 'result' => nil }], parse_written_messages(@fake_out.string)
  end

  def test_exit_without_shutdown_exits_one
    io = io_for_session([{ jsonrpc: '2.0', method: 'exit' }])
    error = assert_raises(SystemExit) { io.send(:run_loop) }

    assert_equal 1, error.status
    assert_equal '', @fake_out.string
  end

  def test_request_after_shutdown_gets_invalid_request
    io = io_for_session([{ jsonrpc: '2.0', id: 1, method: 'shutdown', params: nil },
                         { jsonrpc: '2.0', id: 2, method: 'textDocument/documentSymbol', params: {} },
                         { jsonrpc: '2.0', method: 'textDocument/didClose', params: {} },
                         { jsonrpc: '2.0', method: 'exit' }])
    error = assert_raises(SystemExit) { io.send(:run_loop) }

    assert_equal 0, error.status
    replies = parse_written_messages(@fake_out.string)
    assert_equal([1, 2], replies.map { |m| m['id'] })
    assert_equal(-32_600, replies[1]['error']['code'])
    assert_includes replies[1]['error']['message'], 'textDocument/documentSymbol'
  end

  private

  # An IO wired to a real Server, reading the given messages framed as a client sends them.
  # If the loop runs out of input, get_request calls exit!(1), which would kill the test
  # process, so make that raise instead.
  def io_for_session(messages)
    input = messages.map do |m|
      json = m.to_json
      "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
    end.join
    io = RubyLanguageServer::IO.allocate
    io.send(:in=, StringIO.new(input))
    io.send(:out=, @fake_out)
    io.instance_variable_set(:@server, RubyLanguageServer::Server.new(Mutex.new))
    io.define_singleton_method(:exit!) { |status = 1| raise "ran out of input (exit!(#{status}))" }
    io
  end

  def parse_written_messages(output)
    data = output.b
    messages = []
    until data.empty?
      header, rest = data.split("\r\n\r\n", 2)
      length = header[/Content-Length: (\d+)/, 1].to_i
      messages << JSON.parse(rest.byteslice(0, length).force_encoding(Encoding::UTF_8))
      data = rest.byteslice(length..) || ''.b
    end
    messages
  end

  def io_for_request(request, server = Object.new)
    json = request.to_json
    io = RubyLanguageServer::IO.allocate
    io.send(:in=, StringIO.new("Content-Length: #{json.bytesize}\n#{json}\r\n"))
    io.send(:out=, @fake_out)
    io.instance_variable_set(:@server, server)
    def io.busy_retry_delay = 0 # keep the busy-retry tests fast
    io
  end

  # A server whose on_test_method runs the given block and counts its calls.
  def counting_server(&block)
    handler = block
    server = Object.new
    server.instance_variable_set(:@calls, 0)
    server.define_singleton_method(:calls) { @calls }
    server.define_singleton_method(:on_test_method) do |params|
      @calls += 1
      handler.call(@calls, params)
    end
    server
  end

  # Parses one framed message, checking that Content-Length is the body's byte count.
  def parse_written_message(output)
    header, body = output.b.split("\r\n\r\n", 2)
    assert_equal body.bytesize, header[/Content-Length: (\d+)/, 1].to_i
    JSON.parse(body.force_encoding(Encoding::UTF_8))
  end

  def assert_content_length_matches_body_bytes(output, key)
    header, body = output.b.split("\r\n\r\n", 2)
    declared = header[/Content-Length: (\d+)/, 1].to_i
    assert_equal body.bytesize, declared
    body = body.force_encoding(Encoding::UTF_8)
    assert_operator declared, :>, body.length
    assert_equal 'Café ☕', JSON.parse(body)[key]['name']
  end
end
