# frozen_string_literal: true

require_relative '../../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::ScopeData::Variable do
  let(:scope) { RubyLanguageServer::ScopeData::Scope.new(nil, RubyLanguageServer::ScopeData::Base::TYPE_CLASS, 'some_scope', 1, 100) }
  let(:variable) { RubyLanguageServer::ScopeData::Variable.new(scope, 'some_varible', 2, 2) }
  let(:constant) { RubyLanguageServer::ScopeData::Variable.new(scope, 'SOME_CONSTANT', 2, 2) }
  let(:ivar) { RubyLanguageServer::ScopeData::Variable.new(scope, '@some_ivar', 2, 2) }

  describe '.constant?' do
    it 'should work!' do
      refute(variable.constant?)
      refute(ivar.constant?)
      assert(constant.constant?)
    end
  end
end
