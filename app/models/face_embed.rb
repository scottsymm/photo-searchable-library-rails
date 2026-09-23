class FaceEmbed < ApplicationRecord
  belongs_to :face
  validates :embed, presence: true

  def vector
    embed.unpack("e*")
  end
end
