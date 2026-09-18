class Setting < ApplicationRecord
  self.primary_key = "key"

  def self.get(key, default = nil)
    find_by(key: key)&.value || default
  end

  def self.set_value(key, value)
    record = find_or_initialize_by(key: key)
    record.value = value
    record.save!
  end

  def self.all_map
    order(:key).pluck(:key, :value).to_h
  end
end
