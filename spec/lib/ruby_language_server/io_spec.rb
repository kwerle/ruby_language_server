# frozen_string_literal: true

# require 'spec_helper'
require 'stringio'
require 'json'
require_relative '../../../lib/ruby_language_server/io'

describe RubyLanguageServer::IO do
  let(:fake_in) { StringIO.new }
  let(:fake_out) { StringIO.new }
  let(:server) { Object.new }
  let(:mutex) { Object.new }

  before do
    # Patch ENV to ensure stdio mode
    allow(ENV).to receive(:[]).with('LSP_PORT').and_return(nil)
  end

  describe '#initialize' do
    it 'sets up stdio streams and assigns server.io' do
      allow_any_instance_of(RubyLanguageServer::IO).to receive(:configure_io) do |io_instance|
        io_instance.send(:in=, fake_in)
        io_instance.send(:out=, fake_out)
        io_instance.instance_variable_set(:@using_socket, false)
      end
      def server.io=(val); @io = val; end
      thread = Thread.new do
        begin
          RubyLanguageServer::IO.new(server, mutex)
        rescue SystemExit; end
      end
      sleep 0.05
      expect(server.instance_variable_get(:@io)).to be_a(RubyLanguageServer::IO)
      thread.kill
    end
  end

  describe '#return_response' do
    it 'writes a JSON-RPC response to the output' do
      io = RubyLanguageServer::IO.allocate
      io.send(:out=, fake_out)
      io.send(:return_response, 1, {foo: 'bar'})
      expect(fake_out.string).to include('Content-Length:')
      expect(fake_out.string).to include('jsonrpc')
      expect(fake_out.string).to include('foo')
    end
  end

  describe '#send_notification' do
    it 'writes a JSON-RPC notification to the output' do
      io = RubyLanguageServer::IO.allocate
      io.send(:out=, fake_out)
      io.send(:send_notification, 'testMethod', {foo: 'bar'})
      expect(fake_out.string).to include('Content-Length:')
      expect(fake_out.string).to include('testMethod')
      expect(fake_out.string).to include('foo')
    end
  end

  describe '#get_length' do
    it 'returns the correct length from header' do
      io = RubyLanguageServer::IO.allocate
      expect(io.send(:get_length, 'Content-Length: 42')).to eq(42)
    end
    it 'returns 0 for nil' do
      io = RubyLanguageServer::IO.allocate
      expect(io.send(:get_length, nil)).to eq(0)
    end
  end

  describe '#get_initial_request_line' do
    it 'reads a line from input' do
      io = RubyLanguageServer::IO.allocate
      fake_in.string = "Content-Length: 42\n"
      io.send(:in=, fake_in)
      expect(io.send(:get_initial_request_line)).to eq("Content-Length: 42\n")
    end
  end

  describe '#get_content' do
    it 'reads the specified number of bytes from input' do
      io = RubyLanguageServer::IO.allocate
      fake_in.string = 'abcdefg'
      io.send(:in=, fake_in)
      expect(io.send(:get_content, 3)).to eq('abc')
    end
  end

  describe '#get_request' do
    it 'reads a request body of the expected length' do
      io = RubyLanguageServer::IO.allocate
      header = "Content-Length: 5\n"
      body = "abcde\r\n"
      fake_in = StringIO.new(header + body)
      io.send(:in=, fake_in)
      expect(io.send(:get_request)).to include('abcde')
    end
  end

  describe '#process_request' do
    it 'calls the correct server method and returns the response' do
      # Prepare a fake server with a method matching the request
      server = Object.new
      def server.on_test_method(params); { result: params['foo'] }; end
      # Prepare a request
      request = { id: 1, method: 'test_method', params: { 'foo' => 'bar' } }.to_json
      header = "Content-Length: #{request.bytesize}\n"
      body = request + "\r\n"
      fake_in = StringIO.new(header + body)
      io = RubyLanguageServer::IO.allocate
      io.send(:in=, fake_in)
      io.instance_variable_set(:@server, server)
      result = io.send(:process_request)
      expect(result).to eq([1, { result: 'bar' }])
    end

    it 'returns nil and logs if server does not respond to method' do
      server = Object.new
      request = { id: 1, method: 'no_such_method', params: {} }.to_json
      header = "Content-Length: #{request.bytesize}\n"
      body = request + "\r\n"
      fake_in = StringIO.new(header + body)
      io = RubyLanguageServer::IO.allocate
      io.send(:in=, fake_in)
      io.instance_variable_set(:@server, server)
      expect(io.send(:process_request)).to be_nil
    end
  end
end
