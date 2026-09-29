class CreateSolidQueueTables < ActiveRecord::Migration[8.1]
  def change
    load Rails.root.join("db/queue_schema.rb")
    execute "DELETE FROM schema_migrations WHERE version = '1'"
  end
end
