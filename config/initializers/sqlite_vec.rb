require "sqlite_vec"

module SqliteVecConnection
  def configure_connection
    super
    @raw_connection.enable_load_extension(true)
    SqliteVec.load(@raw_connection)
  end
end

ActiveSupport.on_load(:active_record_sqlite3adapter) do
  prepend SqliteVecConnection
end
