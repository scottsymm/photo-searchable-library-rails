class AddLeaseTokenToSourceSyncs < ActiveRecord::Migration[7.0]
  def change
    add_column :source_syncs, :lease_token, :string
    add_index :source_syncs, :lease_token, unique: true
  end
end
