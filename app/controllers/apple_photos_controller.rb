class ApplePhotosController < ApplicationController
  def status
    source = ApplePhotosBridge.source_with_bridge_status
    imported = source.assets.not_deleted.joins(:content_embed).count
    render json: { source: ApplePhotosBridge.source_json(source).merge(imported_count: imported) }
  end

  def sync
    result = ApplePhotosBridge.sync_request(
      limit: (params[:limit] || 25).to_i,
      full: params[:full] == true || params[:full].to_s == "true" || params[:full].to_s == "1"
    )
    if request.format.html?
      notice = result[:already_active] ? "An Apple Photos import is already in progress." : "Apple Photos import queued."
      redirect_to "/catalog/overview", notice: notice
    else
      render json: { sync: ApplePhotosBridge.sync_json(result[:sync]), already_active: result[:already_active] }
    end
  end

  def sync_status
    render json: { sync: ApplePhotosBridge.sync_json(ApplePhotosBridge.sync_status[:sync]) }
  end

  def claim
    render json: { sync: ApplePhotosBridge.sync_json(ApplePhotosBridge.claim[:sync]) }
  end

  def complete
    result = ApplePhotosBridge.complete(
      params[:id],
      lease_token: params[:lease_token],
      imported_count: params[:imported_count],
      failed_count: params[:failed_count],
      error: params[:error]
    )
    render json: { sync: ApplePhotosBridge.sync_json(result[:sync]) }
  end

  def known
    render json: ApplePhotosBridge.known(params[:source_asset_ids])
  end

  def heartbeat
    result = ApplePhotosBridge.heartbeat(
      authorization_state: params[:authorization_state],
      asset_count: params[:asset_count],
      sync_id: params[:sync_id],
      lease_token: params[:lease_token]
    )
    render json: { source: ApplePhotosBridge.source_json(result[:source]) }
  end

  def ingest
    file = params.require(:file)
    source_asset_id = params.require(:source_asset_id)
    result = ApplePhotosBridge.ingest(
      file: file,
      source_asset_id: source_asset_id,
      original_filename: params[:original_filename],
      media_type: params[:media_type],
      taken_at: params[:taken_at],
      authorization_state: params[:authorization_state],
      asset_count: params[:asset_count]
    )
    render json: result
  end
end
