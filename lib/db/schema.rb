# frozen_string_literal: true

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
