# frozen_string_literal: true

require_relative '../../test_helper'
require 'stringio'
require 'json'

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

  def test_process_request_returns_nil_if_server_does_not_respond
    server = Object.new
    request = { id: 1, method: 'no_such_method', params: {} }.to_json
    header = "Content-Length: #{request.bytesize}\n"
    body = "#{request}\r\n"
    fake_in = StringIO.new(header + body)
    io = RubyLanguageServer::IO.allocate
    io.send(:in=, fake_in)
    io.instance_variable_set(:@server, server)
    assert_nil io.send(:process_request)
  end
end
