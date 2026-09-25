class AddActiveSourceSyncUniqueIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :source_syncs, :source_id,
      unique: true,
      where: "status IN ('queued', 'running')",
      name: "index_source_syncs_on_source_id_active"
  end
end
