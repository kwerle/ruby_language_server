# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::GoodCop do
  before :each do
    RubyLanguageServer::ProjectManager.new('/foo', 'file:///remote') # GoodCop looks to the ProjectManager to get the project root path
  end

  let(:good_cop) { RubyLanguageServer::GoodCop.instance }

  describe 'crashing' do
    it "must survive init failures" do
      raise_exception = -> { raise 'exception!' }
      RuboCop::ConfigStore.stub(:new, raise_exception) do
        RubyLanguageServer::GoodCop.instance
      end
    end
  end

  describe 'basics' do
    it 'should init without config' do
      refute_nil(good_cop)
    end
  end

  describe 'offenses' do
    it 'must lint' do
      offenses = good_cop.send(:offenses, "# frozen_string_literal: true\n\ndef BAD\n  true\nend\n", 'whatever.rb')
      assert_equal(['Naming/MethodName: Use snake_case for method names.'], offenses.map(&:message))
    end

    it 'must lint two things' do
      offenses = good_cop.send(:offenses, "# frozen_string_literal: true\n\ndef BAD\n  fooBar=1\nend\n", 'whatever.rb')
      assert_equal(['Layout/SpaceAroundOperators: Surrounding space missing for operator `=`.', 'Lint/UselessAssignment: Useless assignment to variable - `fooBar`.', 'Naming/MethodName: Use snake_case for method names.', 'Naming/VariableName: Use snake_case for variable names.'], offenses.map(&:message))
    end
  end

  describe 'diagnostics' do
    it 'must lint' do
      diagnostics = good_cop.diagnostics("# frozen_string_literal: true\n\ndef BAD\n  true\nend\n", 'foo.rb')
      assert_equal([{:range => {:start => {:line => 2, :character => 4}, :end => {:line => 2, :character => 7}}, :severity => 3, :code => "code", :source => "RuboCop:Naming/MethodName", :message => "Naming/MethodName: Use snake_case for method names."}], diagnostics)
    end
  end
end
