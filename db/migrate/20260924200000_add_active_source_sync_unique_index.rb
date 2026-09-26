class AddActiveSourceSyncUniqueIndex < ActiveRecord::Migration[8.1]
  def change
    active_syncs = connection.select_all(<<~SQL)
      SELECT source_id, id, status
      FROM source_syncs
      WHERE status IN ('queued', 'running')
      ORDER BY source_id,
        CASE WHEN status = 'running' THEN 0 ELSE 1 END,
        id
    SQL
    retained_source_ids = {}
    active_syncs.each do |sync|
      source_id = sync.fetch("source_id")
      if retained_source_ids.key?(source_id)
        execute <<~SQL
          UPDATE source_syncs
          SET status = 'error',
              error = 'superseded duplicate active sync',
              completed_at = CURRENT_TIMESTAMP,
              updated_at = CURRENT_TIMESTAMP
          WHERE id = #{connection.quote(sync.fetch("id"))}
        SQL
      else
        retained_source_ids[source_id] = sync.fetch("id")
      end
    end

    add_index :source_syncs, :source_id,
      unique: true,
      where: "status IN ('queued', 'running')",
      name: "index_source_syncs_on_source_id_active"
  end
end
