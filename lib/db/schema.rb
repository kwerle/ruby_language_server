# frozen_string_literal: true

module Schema
  class << self
    def load
      ActiveRecord::Schema.define do
        def write(*args)
          RubyLanguageServer.logger.debug(args)
        end

        create_table :scopes, force: true do |t|
          t.references :code_file
          t.integer :parent_id
          t.integer :top_line        # first line
          t.integer :bottom_line     # last line
          t.integer :column
          t.string  :name, default: ''
          t.string  :superclass_name
          t.string  :path
          t.string  :class_type, null: false
          t.text    :parameters      # JSON string of method parameters
          t.boolean :class_method, default: false # true for class methods (def self.method)
        end

        add_index :scopes, :name
        add_index :scopes, :path
        add_index :scopes, :code_file

        create_table :variables, force: true do |t|
          t.references :code_file
          t.references :scope
          t.integer :line
          t.integer :column
          t.string  :name
          t.string  :path
          t.string  :variable_type
        end

        add_index :variables, :name
        add_index :variables, :code_file

        create_table :code_files, force: true do |t|
          t.string  :uri
          t.boolean :refresh_root_scope, default: true
          t.text    :text
        end

        add_index :code_files, :uri
      end
    end

    # If we dive in using a console attached to a running container we do NOT want to reset all the table data!
    # Which it seems like sqlite is happy to do?
    # So we utter some arcane sqlite code to find the existing tables if there are any.
    def already_initialized
      response = ActiveRecord::Base.connection_pool.with_connection { |con| con.exec_query "SELECT name  FROM sqlite_master WHERE type='table'" }
      response.rows.flatten.member?('code_files')
    rescue ExceptionName
      false
    end

    def initialize_if_needed
      load unless already_initialized
    end
  end
end

Schema.initialize_if_needed
