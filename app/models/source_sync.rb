class SourceSync < ApplicationRecord
  belongs_to :source

  after_commit :broadcast_catalog, on: [ :create, :update ]

  private

  def broadcast_catalog
    Turbo::StreamsChannel.broadcast_replace_later_to "catalog",
      target: "catalog_overview",
      partial: "catalog/overview",
      locals: { overview: CatalogOverview.call }
  end
end
