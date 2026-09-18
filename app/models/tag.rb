class Tag < ApplicationRecord
  self.table_name = "tags"
  belongs_to :asset
end
