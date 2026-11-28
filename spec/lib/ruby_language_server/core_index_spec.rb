# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'

describe RubyLanguageServer::CoreIndex do
  let(:scope_class) { RubyLanguageServer::ScopeData::Scope }

  before do
    RubyLanguageServer::CoreIndex.load!(only: %w[String Symbol Integer Numeric File File::Stat Kernel Exception StandardError])
  end

  it 'stores core classes without a location, since the editor cannot open them' do
    string = scope_class.find_by(path: 'String')

    assert_equal 'class', string.class_type
    assert_nil string.code_file
    assert_nil string.top_line
    assert RubyLanguageServer::CoreIndex.loaded?
  end

  it 'stores a class declared in several files once, with all its methods' do
    assert_equal 1, scope_class.where(path: 'Kernel').count
    assert scope_class.find_by(path: 'Kernel#puts')
    assert scope_class.find_by(path: 'Kernel#require')
  end

  it 'stores methods with their signatures, parameters and documentation' do
    each_line = scope_class.find_by(path: 'String#each_line')

    assert_equal 'method', each_line.class_type
    assert_equal scope_class.find_by(path: 'String'), each_line.parent
    assert_includes each_line.signature.lines(chomp: true), '(?string? separator, ?chomp: boolish) { (String line) -> void } -> self'
    assert_equal [{ 'name' => 'separator', 'type' => 'optional' }, { 'name' => 'chomp:', 'type' => 'keyword' }], each_line.parsed_parameters
    refute_includes each_line.documentation, 'rdoc-file'
    assert_includes each_line.documentation, 'line'
  end

  it 'names unnamed parameters after their type' do
    assert_equal [{ 'name' => 'numeric', 'type' => 'required' }], scope_class.find_by(path: 'Integer#coerce').parsed_parameters
    assert_equal [{ 'name' => '*selector', 'type' => 'rest' }], scope_class.find_by(path: 'String#strip').parsed_parameters
  end

  it 'stores aliases as methods' do
    assert_equal scope_class.find_by(path: 'Integer#succ').signature, scope_class.find_by(path: 'Integer#next').signature
  end

  it 'stores aliases of module functions both ways' do
    assert_equal [false, true], scope_class.where(path: 'Kernel#fail').order(:class_method).pluck(:class_method)
    assert_equal scope_class.find_by(path: 'Kernel#raise').signature, scope_class.find_by(path: 'Kernel#fail').signature
  end

  it 'marks singleton methods and stores module functions both ways' do
    refute scope_class.find_by(path: 'String#upcase').class_method
    assert scope_class.find_by(path: 'File#exist?', class_method: true)
    assert_equal [false, true], scope_class.where(path: 'Kernel#puts').order(:class_method).pluck(:class_method)
  end

  it 'stores superclasses so inherited methods are found' do
    integer = scope_class.find_by(path: 'Integer')

    assert_equal 'Numeric', integer.superclass_name
    assert_equal ['Numeric'], integer.ancestor_class_scopes.map(&:path)
  end

  it 'stores nested classes by their full path' do
    stat = scope_class.find_by(path: 'File::Stat')

    assert_equal 'Stat', stat.name
    assert_equal 'class', stat.class_type
    assert_equal scope_class.find_by(path: 'File'), stat.parent
  end

  it 'stores only the classes asked for' do
    assert_nil scope_class.find_by(path: 'Array')
  end

  it 'does nothing when core is already stored' do
    count = scope_class.count
    RubyLanguageServer::CoreIndex.load!

    assert_equal count, scope_class.count
  end

  describe 'with a project' do
    let(:project_manager) { RubyLanguageServer::ProjectManager.new('/proj', 'file:///proj/') }

    def index(uri, source)
      project_manager.update_document_content(uri, source)
      project_manager.tags_for_uri(uri) # parse it
    end

    def hover(uri, line, character)
      project_manager.hover_at(uri, OpenStruct.new(line:, character:))&.dig(:contents, :value)
    end

    it 'hovers a core method with its signatures and documentation' do
      index('file:///proj/a.rb', "name = 'x'\nname.each_line\n")
      markdown = hover('file:///proj/a.rb', 1, 7)

      assert markdown.start_with?("```ruby\ndef each_line: "), markdown
      assert_includes markdown, 'In `String`'
      assert_includes markdown, 'With a block given, forms the substrings'
    end

    it 'prefers the project definition over core' do
      index('file:///proj/b.rb', "class Shouter\n  def upcase\n  end\nend\nname.upcase\n")
      definitions = project_manager.possible_definitions('file:///proj/b.rb', OpenStruct.new(line: 4, character: 7))

      assert_equal(['file:///proj/b.rb'], definitions.pluck(:uri))
      assert_equal "```ruby\ndef upcase\n```\n\nIn `Shouter`", hover('file:///proj/b.rb', 4, 7)
    end

    it 'finds a project method when a core ancestor defines the name too' do
      index('file:///proj/e.rb', "class MyError < StandardError\n  def report\n    message\n  end\nend\nclass Other\n  def message\n  end\nend\n")
      definitions = project_manager.possible_definitions('file:///proj/e.rb', OpenStruct.new(line: 2, character: 6))

      assert_equal([{ uri: 'file:///proj/e.rb', line: 6 }], definitions.map { |definition| { uri: definition[:uri], line: definition[:range][:start][:line] } })
    end

    it "hovers the project's override of a reopened core class" do
      index('file:///proj/f.rb', "class String\n  def self.try_convert(object)\n  end\nend\nString.try_convert\n")

      assert_equal "```ruby\ndef self.try_convert(object)\n```\n\nIn `String`", hover('file:///proj/f.rb', 4, 10)
    end

    it 'lists every core class a method could be from when the receiver is unknown' do
      index('file:///proj/g.rb', "name.upcase\n")
      markdown = hover('file:///proj/g.rb', 0, 7)

      assert_includes markdown, 'In `String`'
      assert_includes markdown, 'In `Symbol`'
      refute_includes markdown, 'Returns a new string'
    end

    it 'completes project classes when many core names tie with them' do
      # Same prefix as the project's class, so the database ranks them equal, and older ids.
      rows = ('a'..'y').map { |letter| { name: "Str#{'q' * 30}#{letter}", path: "Str#{'q' * 30}#{letter}", class_type: 'class' } }
      scope_class.insert_all!(rows)
      index('file:///proj/h.rb', "class Strongbox\nend\nStr\n")
      labels = project_manager.completion_at('file:///proj/h.rb', OpenStruct.new(line: 2, character: 3))[:items].pluck(:label)

      assert_includes labels, 'Strongbox'
    end

    it 'has no definition location for a core method' do
      index('file:///proj/d.rb', "name.upcase\n")

      assert_empty project_manager.possible_definitions('file:///proj/d.rb', OpenStruct.new(line: 0, character: 7))
    end

    it 'completes core methods after a core class' do
      index('file:///proj/c.rb', "String.up\n")
      labels = project_manager.completion_at('file:///proj/c.rb', OpenStruct.new(line: 0, character: 9))[:items].pluck(:label)

      assert(labels.any? { |label| label.start_with?('upcase') }, labels.inspect)
    end
  end
end
