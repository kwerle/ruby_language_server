# frozen_string_literal: true

require_relative 'spec/test_helper'
require 'minitest/autorun'

describe 'Fallback behavior' do
  let(:project_manager) { RubyLanguageServer::ProjectManager.new('/proj', 'file:///foo/') }

  it 'should test current behavior when nothing found in scope' do
    # Define a class in one file
    other_file = <<~CODE
      class MyExternalClass
        def external_method
        end
      end
    CODE
    
    # Reference it from another file where it's not in scope
    file_text = <<~CODE
      module SomeModule
        class SomeClass
          def some_method
            MyExternalClass # Exists elsewhere but not in local scope
          end
        end
      end
    CODE

    project_manager.update_document_content('other_uri', other_file)
    project_manager.tags_for_uri('other_uri') # Force load
    
    project_manager.update_document_content('test_uri', file_text)
    project_manager.tags_for_uri('test_uri') # Force load

    # Try to find MyExternalClass from test_uri
    position = OpenStruct.new(line: 3, character: 6)
    results = project_manager.possible_definitions('test_uri', position)
    puts "Results for MyExternalClass (should find it globally): #{results.inspect}"
    puts "Expected to find definition in other_uri"
  end
  
  it 'should test when constant truly does not exist' do
    file_text = <<~CODE
      module SomeModule
        class SomeClass
          def some_method
            TotallyNonExistentClass # This truly doesn't exist anywhere
          end
        end
      end
    CODE

    project_manager.update_document_content('test_uri', file_text)
    project_manager.tags_for_uri('test_uri') # Force load

    # Try to find non-existent constant
    position = OpenStruct.new(line: 3, character: 6)
    results = project_manager.possible_definitions('test_uri', position)
    puts "Results for TotallyNonExistentClass (shouldn't find anything): #{results.inspect}"
  end
end
