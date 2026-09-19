class AssetsController < ApplicationController
  def thumbnail
    asset = Asset.not_deleted.find_by(id: params[:id])
    stored = asset && StoredFile.find_by(id: asset.thumbnail_id)
    raise ActiveRecord::RecordNotFound if stored.nil? || stored.bytes.nil?
    send_data stored.bytes, type: "image/jpeg", disposition: "inline"
  end
end
