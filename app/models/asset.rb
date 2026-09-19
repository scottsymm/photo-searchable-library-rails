class Asset < ApplicationRecord
  belongs_to :source, optional: true
  has_one :content_embed
  has_many :faces
  has_many :tags

  scope :not_deleted, -> { where(deleted: 0) }

  def thumbnail_url
    "/assets/#{id}/thumbnail"
  end
end
