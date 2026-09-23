---
title: Rails Port Phase 3 — Outside-in UI Feature Parity
tags:
  - plan
  - rails-port
  - phase-3
  - ui
  - hotwire
created: 2026-09-23
---

# Rails Port Phase 3 — Outside-in UI Feature Parity

*Created: 2026-09-23*

**Goal:** Match the reference app's five-page UI **feature surface** — Home
search, Photos (catalog), People, Places, Settings — built **the Rails way**
(server-rendered ERB + Turbo + Stimulus), not pixel-identical to the React UI.

**Architecture:** The Phase 1/2 Rails backend already implements the JSON
contract. This plan adds/rewrites the view layer and the handful of missing
endpoints (`/places`, admin `disk`, `/persons/search`, people `enrichment`),
then styles it by porting the reference stylesheet (framework-agnostic CSS) so
the app looks and behaves like the reference without React. Interactive
behaviors (tabs, funnel drilldown, debounced person picker, thumbnail fallback)
are small Stimulus controllers.

> **Live data — the current Rails way (server-push Turbo Streams):** the
> reference app polls JSON every 3s. The Rails 8 idiom is the opposite: Solid
> Queue jobs **broadcast** Turbo Streams to channels, and pages subscribe with
> `<%= turbo_stream_from ... %>`, so the DOM updates the moment work finishes —
> zero polling, zero client timers. In this plan:
> * the domain `Job` model broadcasts its own card to the `"jobs"` stream on
>   every create/update (`progress`, `status`, `error`);
> * `ImportJob` broadcasts the catalog overview region to `"catalog"` when an
>   import completes;
> * `ClusterFacesJob` broadcasts the people review queue to `"people"` when a
>   clustering run finishes;
> * pages that render these regions include `turbo_stream_from "jobs"`,
>   `"catalog"`, or `"people"` and render shared partials that the broadcasts
>   re-render.
>
> This works in the Docker dev stack even though the worker runs in a separate
> container, because **Solid Cable** is used in development too (dev
> `cable.yml` → `solid_cable` adapter backed by a dev cable database), not the
> same-process `async` adapter. Turbo 8.0.23 (bundled by turbo-rails 2.0.23,
> the newest release — no 8.1 exists) fully supports `turbo_stream_from`,
> `broadcast_*_to`, and the `turbo-stream-source` element; the vendored
> `turbo.js` includes all of them. No `data-turbo-refresh-period` (which does
> not exist in any Turbo release) is needed.

**Tech Stack:** Rails 8.1, ERB + Turbo Frames + Turbo Streams (server-push),
Stimulus (importmap), Solid Cable + Solid Queue, Propshaft, jbuilder, Minitest.

**Source:** Reference UI in `/Users/jobofish/code/pics/apps/web` (read-only):
`app/page.tsx` (home search), `app/photos/page.tsx`, `app/people/page.tsx`,
`app/places/page.tsx`, `app/settings/page.tsx`, `app/globals.css`,
`components/Nav.tsx`, `lib/search-parser.ts`, `lib/api.ts`, `lib/funnel.ts`,
`types.ts`.

**Out of scope (deferred):** Apple Photos bridge sync actions (Phase 4), watch
backfill radios (kept minimal — backfill flow needs the watcher), CLI, deploy,
video face extraction.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `app/assets/stylesheets/application.css` | Replace | Port reference `globals.css` (framework-agnostic) |
| `app/helpers/application_helper.rb` | Create | Funnel stage meta, badge/status labels, proportion % helpers |
| `app/services/search_query.rb` | Create | Port of `lib/search-parser.ts` (server-side) |
| `test/services/search_query_test.rb` | Create | Parser tests |
| `app/controllers/search_controller.rb` | Modify | Use `SearchQuery.parse` |
| `app/controllers/health_controller.rb` | Modify | HTML renders search hero; JSON stays `{ok:true}` |
| `app/views/search/_hero.html.erb` | Create | Hero + single search input + results frame |
| `app/views/search/index.html.erb` | Replace | Renders `_hero` |
| `app/views/health/dashboard.html.erb` | Delete | Superseded by search hero |
| `app/controllers/places_controller.rb` | Create | `GET /places` aggregate |
| `app/views/places/index.html.erb` | Create | Places cards |
| `test/controllers/places_controller_test.rb` | Create | JSON + HTML tests |
| `app/controllers/catalog_controller.rb` | Modify | Load overview; no polling vars |
| `app/views/catalog/overview.html.erb` | Replace | Photos page: funnel + context + recent + sources |
| `app/views/catalog/_overview.html.erb` | Create | Stream-renderable overview body (shared with broadcasts) |
| `app/views/catalog/_source_card.html.erb` | Create | Source connection card partial |
| `app/models/person.rb` | Modify | Add `face_count`, `representative_url` |
| `app/models/cluster_suggestion.rb` | Modify | Add `face_count`, `representative_url` |
| `app/models/job.rb` | Modify | Broadcast card to `"jobs"` on create/update |
| `app/views/jobs/_job.html.erb` | Create | Stream-renderable job card (shared by `/jobs` + settings) |
| `app/jobs/import_job.rb` | Modify | Broadcast `"catalog"` overview when import completes |
| `app/jobs/cluster_faces_job.rb` | Modify | Broadcast `"people"` review queue when run completes |
| `config/cable.yml` | Modify | dev → `solid_cable` adapter |
| `config/database.yml` | Modify | dev `cable` database entry |
| `app/services/face_enrichment.rb` | Create | Enrichment hash shared by `PersonsController` + `ClusterFacesJob` |
| `app/controllers/persons_controller.rb` | Modify | Add `search` action + `FaceEnrichment.call` |
| `app/controllers/person_suggestions_controller.rb` | Modify | `confirm` accepts `name` |
| `app/views/persons/index.json.jbuilder` | Create | Reference `Person`/`ClusterSuggestion`/`enrichment` shapes |
| `app/views/persons/search.json.jbuilder` | Create | Picker response |
| `config/routes.rb` | Modify | `places`, `settings`, `persons/search` → `search` |
| `app/views/persons/index.html.erb` | Replace | Tabs + enrichment + cluster button + show-rejected toggle + `turbo_stream_from "people"` |
| `app/views/persons/_review_queue.html.erb` | Create | Stream-renderable suggestions region (shared with broadcasts) |
| `app/views/persons/_suggestion.html.erb` | Replace | Card: faces, name/picker confirm, reject, restore-when-rejected |
| `app/views/persons/_person.html.erb` | Replace | Card: rename, aliases, merge, split |
| `app/views/persons/_person_picker.html.erb` | Create | Debounced search input + results + selection |
| `app/javascript/controllers/tabs_controller.js` | Create | Suggestion/Named-people tabs |
| `app/javascript/controllers/funnel_controller.js` | Create | Funnel stage drilldown |
| `app/javascript/controllers/thumbnail_fallback_controller.js` | Create | Broken thumbnail → placeholder |
| `app/javascript/controllers/person_picker_controller.js` | Create | Debounced picker + merge action |
| `app/controllers/admin_controller.rb` | Modify | Add `disk`, jobs, HTML render for status |
| `app/views/admin/status.html.erb` | Create | Settings page + `turbo_stream_from "jobs"` |
| `app/views/layouts/application.html.erb` | Modify | Shell + topbar + nav (no polling/morph attrs) |
| `test/controllers/persons_json_test.rb` | Create | Persons index/search JSON + confirm-with-name |
| `test/controllers/settings_controller_test.rb` | Create | Settings page HTML/JSON |

---

## Tasks

### Task 1: Port the reference stylesheet

**Files:**
- Replace: `app/assets/stylesheets/application.css`

- [ ] **Step 1: Copy the reference stylesheet**

```bash
cp /Users/jobofish/code/pics/apps/web/app/globals.css app/assets/stylesheets/application.css
```

This overwrites the current manifest. The reference CSS is plain, framework
agnostic CSS — no React dependencies. Class names are reused verbatim by the
views in this plan (`.shell`, `.topbar`, `.brand`, `.nav`, `.cards`, `.card`,
`.badge*`, `.funnel*`, `.tabs`, `.tab`, `.faceRow`, `.personSummary`,
`.pickerResults`, `.aliasChip`, `.aliasRow`, `.mergePanel`, `.photo`,
`.photoPlaceholder`, `.thumbRow`, `.proportionBar`, `.contextValue`,
`.contextMeta`, `.cardLink`, `.enrichmentCard`, `.button`, `.secondary`,
`.muted`, `.searchInput`, `.searchForm`, `.hint`, `.status`, `.lead`,
`.eyebrow`, `.sourceFacts`, `.mountPaths`, `.mountLabel`, `.mountState`,
`.nextStep`, `.setupDetails`, `.commandRow`, `.copyButton`, `.dialog*`).

- [ ] **Step 2: Verify**

Run: `wc -l app/assets/stylesheets/application.css`
Expected: ~330 lines (reference file length), and `grep -c "funnelStage" app/assets/stylesheets/application.css`
returns `2` or more.

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/application.css
git commit -q -m "style: port reference globals stylesheet"
```

---

### Task 2: SearchQuery service (port of search-parser.ts)

**Files:**
- Create: `app/services/search_query.rb`
- Test: `test/services/search_query_test.rb`

- [ ] **Step 1: Write the parser**

```ruby
# app/services/search_query.rb
class SearchQuery
  FIELDS = %w[who place before after tag].freeze

  def self.parse(raw)
    result = { text: "" }
    free = []
    raw.to_s.strip.split(/\s+/).reject(&:blank?).each do |token|
      if (match = token.match(/^(who|place|before|after|tag):(.+)$/i))
        result[match[1].downcase] = match[2]
      else
        free << token
      end
    end
    result[:text] = free.join(" ")
    result
  end
end
```

- [ ] **Step 2: Write the test**

```ruby
# test/services/search_query_test.rb
require "test_helper"

class SearchQueryTest < ActiveSupport::TestCase
  test "extracts free text and structured filters" do
    parsed = SearchQuery.parse("picnic who:Sam place:Lisbon before:2020")
    assert_equal "picnic", parsed[:text]
    assert_equal "Sam", parsed[:who]
    assert_equal "Lisbon", parsed[:place]
    assert_equal "2020", parsed[:before]
  end

  test "handles empty and whitespace input" do
    assert_equal({ text: "" }, SearchQuery.parse(""))
    assert_equal({ text: "" }, SearchQuery.parse("   "))
  end

  test "keeps unknown prefixes as free text" do
    assert_equal({ text: "color:red picnic" }, SearchQuery.parse("color:red picnic"))
  end

  test "is case insensitive for field prefixes" do
    parsed = SearchQuery.parse("Who:Sam PLACE:Paris")
    assert_equal "Sam", parsed["who"] || parsed[:who]
    assert_equal "Paris", parsed["place"] || parsed[:place]
  end
end
```

- [ ] **Step 3: Verify (red → green)**

Run: `mise exec -- bin/rails test test/services/search_query_test.rb`
Expected: 4 runs, 0 failures, 0 errors.

- [ ] **Step 4: Commit**

```bash
git add app/services/search_query.rb test/services/search_query_test.rb
git commit -q -m "feat: server-side structured query parser"
```

---

### Task 3: Wire SearchQuery into the search controller

**Files:**
- Modify: `app/controllers/search_controller.rb`

- [ ] **Step 1: Replace the controller**

```ruby
# app/controllers/search_controller.rb
class SearchController < ApplicationController
  def index
    parsed = SearchQuery.parse(params[:q])
    @results = SearchService.search(
      q: parsed[:text], who: parsed[:who], place: parsed[:place],
      before: parsed[:before], after: parsed[:after], tag: parsed[:tag],
      limit: (params[:limit] || 50).to_i
    )
    respond_to do |format|
      format.json { render json: { results: @results } }
      format.html
    end
  end
end
```

- [ ] **Step 2: Verify**

Run: `mise exec -- bin/rails test test/controllers/search_controller_test.rb`
Expected: 2 runs, 0 failures (existing tests still pass with the parser wired in).

- [ ] **Step 3: Commit**

```bash
git add app/controllers/search_controller.rb
git commit -q -m "feat: parse structured filters in search controller"
```

---

### Task 4: Search hero partial + health page

**Files:**
- Create: `app/views/search/_hero.html.erb`
- Replace: `app/views/search/index.html.erb`
- Modify: `app/controllers/health_controller.rb`
- Delete: `app/views/health/dashboard.html.erb`

- [ ] **Step 1: Write the hero partial**

```erb
<%# app/views/search/_hero.html.erb %>
<section class="hero">
  <p class="eyebrow">Private visual archive</p>
  <h1>Find the photo you can almost remember.</h1>
  <p class="lead">Search by what happened, who was there, where it was, or when it happened. Your originals stay on your machine.</p>
</section>

<%= form_tag("/search", method: :get, data: { turbo_frame: "results" }, class: "searchForm") do %>
  <%= search_field_tag :q, params[:q], class: "searchInput", placeholder: "a picnic with Sam in 2021", "aria-label": "Search photos" %>
  <button class="button" type="submit">Search</button>
<% end %>
<p class="hint">Structured filters also work: <code>who:Sam place:Lisbon before:2020</code></p>

<%= turbo_frame_tag "results" do %>
  <p class="status" aria-live="polite"><%= pluralize(@results.length, "result") %></p>
  <div class="grid">
    <% @results.each do |result| %>
      <figure class="photo" data-controller="thumbnail-fallback">
        <img data-thumbnail-fallback-target="image" src="<%= result[:thumbnail_url] %>" alt="<%= result[:taken_at] || result[:path] %>" loading="lazy" data-action="error->thumbnail-fallback#failed">
        <div class="photoPlaceholder" data-thumbnail-fallback-target="fallback" hidden><span>Preview pending</span></div>
        <figcaption><%= result[:taken_at] || result[:place_city] || result[:path] %><% if result[:distance] %> · <%= result[:distance].round(3) %><% end %></figcaption>
      </figure>
    <% end %>
  </div>
<% end %>
```

- [ ] **Step 2: Replace the search index view**

```erb
<%# app/views/search/index.html.erb %>
<% content_for :title, "Search" %>
<%= render "hero" %>
```

- [ ] **Step 3: Point health HTML at the hero**

```ruby
# app/controllers/health_controller.rb
class HealthController < ApplicationController
  def index
    respond_to do |format|
      format.html do
        @results = []
        render "search/index"
      end
      format.json { render json: { ok: true } }
    end
  end
end
```

- [ ] **Step 4: Remove the obsolete dashboard view**

```bash
git rm app/views/health/dashboard.html.erb
```

- [ ] **Step 5: Verify**

```bash
mise exec -- bin/rails test test/controllers/health_controller_test.rb test/controllers/search_controller_test.rb
```

Expected: all green. Then start the server and check the hero renders:

```bash
mise exec -- bin/rails server &
sleep 8
curl -s -H 'Accept: text/html' http://localhost:3000/ | grep -o "Find the photo you can almost remember."
curl -s http://localhost:3000/ | grep -o '"ok":true'
kill %1 2>/dev/null
```

Expected: both greps print a match. The thumbnail-fallback Stimulus controller is
created in Task 9; until then the `data-controller="thumbnail-fallback"` element
is inert (safe).

- [ ] **Step 6: Commit**

```bash
git add app/views/search app/views/health app/controllers/health_controller.rb
git commit -q -m "feat: search hero on root and search pages"
```

---

### Task 5: Places page

**Files:**
- Create: `app/controllers/places_controller.rb`
- Create: `app/views/places/index.html.erb`
- Create: `test/controllers/places_controller_test.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Write the controller**

```ruby
# app/controllers/places_controller.rb
class PlacesController < ApplicationController
  def index
    @places = Asset.not_deleted
                   .where.not(place_city: nil)
                   .group(:place_city, :place_country)
                   .count
                   .map { |(city, country), count| { place_city: city, place_country: country, count: count } }
                   .sort_by { |place| [ -place[:count], place[:place_city] ] }
    respond_to do |format|
      format.json { render json: { places: @places } }
      format.html
    end
  end
end
```

- [ ] **Step 2: Write the view**

```erb
<%# app/views/places/index.html.erb %>
<% content_for :title, "Places" %>
<p class="eyebrow">Geography</p>
<h1>Places</h1>
<p class="lead">A quiet index of where your camera has been.</p>
<div class="cards">
  <% @places.each do |place| %>
    <div class="card">
      <strong><%= place[:place_city] %></strong>
      <span class="muted"><%= place[:place_country] %> · <%= pluralize(place[:count], "photo") %></span>
    </div>
  <% end %>
</div>
<% if @places.empty? %>
  <p class="muted">No places indexed yet.</p>
<% end %>
```

- [ ] **Step 3: Add the route**

```ruby
# config/routes.rb — add inside the routes.draw block, near the other GETs
  get "/places", to: "places#index"
```

- [ ] **Step 4: Write the test**

```ruby
# test/controllers/places_controller_test.rb
require "test_helper"

class PlacesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Asset.create!(path: "/tmp/places/1.jpg", sha256: "pl1", size_bytes: 1, mime: "image/jpeg", place_city: "Lisbon", place_country: "PT")
    Asset.create!(path: "/tmp/places/2.jpg", sha256: "pl2", size_bytes: 1, mime: "image/jpeg", place_city: "Lisbon", place_country: "PT")
    Asset.create!(path: "/tmp/places/3.jpg", sha256: "pl3", size_bytes: 1, mime: "image/jpeg")
  end

  test "returns aggregated places as json" do
    get "/places", as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["places"].length
    assert_equal "Lisbon", body["places"].first["place_city"]
    assert_equal 2, body["places"].first["count"]
  end

  test "renders html page" do
    get "/places"
    assert_response :success
    assert_match "Places", response.body
  end
end
```

- [ ] **Step 5: Verify**

Run: `mise exec -- bin/rails test test/controllers/places_controller_test.rb`
Expected: 2 runs, 0 failures, 0 errors.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/places_controller.rb app/views/places test/controllers/places_controller_test.rb config/routes.rb
git commit -q -m "feat: places index page and endpoint"
```

---

### Task 6: Application helper (funnel meta + labels + proportions)

**Files:**
- Create: `app/helpers/application_helper.rb`

- [ ] **Step 1: Write the helper**

```ruby
# app/helpers/application_helper.rb
module ApplicationHelper
  FUNNEL_STAGES = [
    { key: "discovered", label: "Discovered", approximate: false, tone: "default" },
    { key: "ready_to_import", label: "Ready to import", approximate: false, tone: "default" },
    { key: "importing", label: "Importing", approximate: true, tone: "default" },
    { key: "imported", label: "Imported", approximate: false, tone: "default" },
    { key: "processing", label: "Processing", approximate: false, tone: "default" },
    { key: "searchable", label: "Searchable", approximate: false, tone: "goal" },
    { key: "failed_or_blocked", label: "Failed / Blocked", approximate: true, tone: "bad" }
  ].freeze

  CLUSTERING_LABELS = {
    "ready" => "Clustering ready",
    "completed_no_suggestions" => "Clustering complete · no new groups",
    "indexing" => "Clustering will cover indexed faces",
    "running" => "Clustering in progress",
    "queued" => "Clustering in progress",
    "no_faces" => "No faces indexed yet"
  }.freeze

  def funnel_stages
    FUNNEL_STAGES
  end

  def clustering_status_label(status)
    CLUSTERING_LABELS.fetch(status, "Clustering not ready")
  end

  def assigned_pct(faces)
    faces[:total].zero? ? 0 : (faces[:assigned].to_f / faces[:total] * 100).round
  end

  def located_pct(places)
    total = places[:located] + places[:unlocated]
    total.zero? ? 0 : (places[:located].to_f / total * 100).round
  end

  def source_badge_class(source)
    if source[:kind] == "mounted_folder"
      source[:watch_enabled] ? "badge badgeOk" : "badge badgeMuted"
    else
      "badge badgeMuted"
    end
  end

  def source_badge_label(source)
    case source[:ingest_mode]
    when "manual" then "Manual upload"
    when "watch" then source[:watch_enabled] ? "Watching" : "Watch paused"
    else "Bridge offline"
    end
  end
end
```

- [ ] **Step 2: Verify**

Run: `mise exec -- bin/rails runner 'puts ApplicationHelper.new.funnel_stages.length'`
Expected: `7`.

- [ ] **Step 3: Commit**

```bash
git add app/helpers/application_helper.rb
git commit -q -m "feat: funnel and badge view helpers"
```

---

### Task 7: Photos page (catalog overview rewrite)

**Files:**
- Replace: `app/views/catalog/overview.html.erb`
- Create: `app/views/catalog/_overview.html.erb`
- Create: `app/views/catalog/_source_card.html.erb`
- Modify: `app/controllers/catalog_controller.rb`

- [ ] **Step 1: Replace the catalog controller**

```ruby
# app/controllers/catalog_controller.rb
class CatalogController < ApplicationController
  def overview
    @overview = CatalogOverview.call
    respond_to do |format|
      format.json { render json: @overview }
      format.html
    end
  end
end
```

- [ ] **Step 2: Split the overview body into a stream-renderable partial**

```erb
<%# app/views/catalog/_overview.html.erb %>
<h2>Asset funnel</h2>
<div class="funnel" data-controller="funnel">
  <% funnel_stages.each do |stage| %>
    <% value = overview[:funnel][stage[:key]] %>
    <button type="button" class="funnelStage <%= "funnelStageGoal" if stage[:tone] == "goal" %> <%= "funnelStageBad" if stage[:tone] == "bad" && value > 0 %> <%= "funnelStageApprox" if stage[:approximate] %>"
            data-funnel-target="stage" data-stage-key="<%= stage[:key] %>" aria-pressed="false"
            data-action="click->funnel#toggle">
      <span class="stageLabel"><%= stage[:label] %></span>
      <span class="stageValue"><%= number_with_delimiter(value) %></span>
      <% if stage[:approximate] %><span class="stageApprox">approx</span><% end %>
    </button>
  <% end %>
</div>
<p class="funnelNote">Discovered counts are as of each source's last report. Select a stage for its per-source breakdown.</p>

<% funnel_stages.each do |stage| %>
  <div class="drilldown" data-funnel-target="panel" data-stage-panel="<%= stage[:key] %>" hidden>
    <strong><%= stage[:label] %> — by source</strong>
    <% max = overview[:sources].map { |source| source[:stages][stage[:key]] }.max.to_f %>
    <% overview[:sources].each do |source| %>
      <% value = source[:stages][stage[:key]] %>
      <div class="barRow">
        <span><%= source[:display_name] %></span>
        <span class="barTrack"><span class="barFill" style="width: <%= max.zero? ? 0 : (value / max * 100).round %>%"></span></span>
        <strong><%= number_with_delimiter(value) %></strong>
      </div>
    <% end %>
  </div>
<% end %>

<h2>Catalog context</h2>
<div class="cards">
  <% faces = overview[:context][:faces] %>
  <div class="card">
    <strong>Faces &amp; people</strong>
    <span class="contextValue"><%= number_with_delimiter(faces[:total]) %> faces</span>
    <span class="contextMeta"><%= number_with_delimiter(faces[:assigned]) %> assigned to people · <%= number_with_delimiter(faces[:unassigned]) %> unassigned</span>
    <span class="contextMeta"><%= faces[:embeddings_pending] > 0 ? "#{faces[:embeddings_pending]} face embeddings pending" : "#{faces[:embeddings_ready]} face embeddings ready" %></span>
    <% if faces[:assets_processing] > 0 %><span class="contextMeta"><%= faces[:assets_processing] %> assets still processing</span><% end %>
    <span class="contextMeta"><%= clustering_status_label(faces[:clustering_status]) %></span>
    <%= link_to "Review people", persons_path, class: "cardLink" %>
    <div class="proportionBar"><span style="width: <%= assigned_pct(faces) %>%"></span></div>
  </div>
  <% places = overview[:context][:places] %>
  <div class="card">
    <strong>Places</strong>
    <span class="contextValue"><%= number_with_delimiter(places[:located]) %> located</span>
    <span class="contextMeta"><%= number_with_delimiter(places[:unlocated]) %> assets without location data</span>
    <div class="proportionBar"><span style="width: <%= located_pct(places) %>%"></span></div>
  </div>
</div>

<h2>Recent imports</h2>
<% if overview[:context][:recent_imports].empty? %>
  <p class="muted">No assets imported yet.</p>
<% else %>
  <div class="thumbRow">
    <% overview[:context][:recent_imports].each do |asset| %>
      <figure class="photo" data-controller="thumbnail-fallback">
        <img data-thumbnail-fallback-target="image" src="/assets/<%= asset[:id] %>/thumbnail" alt="<%= asset[:original_filename] || "Asset #{asset[:id]}" %>" loading="lazy" data-action="error->thumbnail-fallback#failed">
        <div class="photoPlaceholder" data-thumbnail-fallback-target="fallback" hidden><span>Preview pending</span></div>
        <figcaption><span class="assetName"><%= asset[:original_filename] || "Asset #{asset[:id]}" %></span><span class="sourceName"><%= asset[:source_kind] %></span></figcaption>
      </figure>
    <% end %>
  </div>
<% end %>

<h2>Source connections</h2>
<div class="cards">
  <% overview[:sources].each do |source| %>
    <%= render partial: "source_card", locals: { source: source } %>
  <% end %>
</div>
```

- [ ] **Step 3: Replace the overview view (page shell + stream subscription)**

```erb
<%# app/views/catalog/overview.html.erb %>
<% content_for :title, "Photos" %>
<%= turbo_stream_from "catalog" %>
<p class="eyebrow">Catalog overview</p>
<h1>Photos</h1>
<p class="lead">The state of your catalog and its connections — where every asset is, and what needs attention.</p>
<div id="catalog_overview">
  <%= render "catalog/overview", overview: @overview %>
</div>
```

- [ ] **Step 4: Write the source card partial**

```erb
<%# app/views/catalog/_source_card.html.erb %>
<div class="card actionCard">
  <strong><%= source[:display_name] %><span class="<%= source_badge_class(source) %>"><%= source_badge_label(source) %></span></strong>
  <div class="sourceFacts">
    <span><%= number_with_delimiter(source[:stages]["discovered"]) %> discovered · <%= number_with_delimiter(source[:stages]["searchable"]) %> searchable</span>
    <% if source[:kind] == "mounted_folder" %>
      <span class="muted"><%= source[:watch_enabled] ? "Watching for new files" : "Continuous watch is paused" %></span>
      <%= link_to "Manage watch settings", "/settings", class: "cardLink" %>
    <% elsif source[:kind] == "uploads" %>
      <span class="muted">Files uploaded directly to Pics</span>
    <% else %>
      <span class="muted">Not configured — Apple Photos sync arrives with the bridge.</span>
    <% end %>
  </div>
</div>
```

- [ ] **Step 5: Verify**

```bash
mise exec -- bin/rails test test/controllers/catalog_controller_test.rb
mise exec -- bin/rails runner 'puts CatalogOverview.call[:funnel].keys.inspect'
```

Expected: tests green and the runner prints the 7 stage keys.

- [ ] **Step 6: Commit**

```bash
git add app/views/catalog app/controllers/catalog_controller.rb
git commit -q -m "feat: photos page with funnel, context, and source cards"
```

---

### Task 8: Solid Cable for development (cross-process broadcasts)

**Files:**
- Modify: `config/database.yml`
- Modify: `config/cable.yml`

Broadcasts originate in the Solid Queue worker container and are delivered to
the web container, so the development adapter must be `solid_cable` (DB-backed
pub/sub), not the same-process `async` adapter.

- [ ] **Step 1: Add a dev cable database to database.yml**

The development block must become a nested `primary` + `cable` configuration,
mirroring the production block. Do **not** keep `<<: *default` at the
`development:` level — that breaks config resolution and lets `db:prepare` dump
the full `structure.sql` (including `vec0_*` virtual tables) into the cable
database.

```yaml
# config/database.yml — replace the development block
development:
  primary:
    <<: *default
    database: storage/development.sqlite3
  cable:
    <<: *default
    database: storage/development_cable.sqlite3
    migrations_paths: db/cable_migrate
```

- [ ] **Step 2: Switch the dev cable adapter**

```yaml
# config/cable.yml — replace the development block
development:
  adapter: solid_cable
  connects_to:
    database:
      writing: cable
  polling_interval: 0.1.seconds
  message_retention: 1.day
```

- [ ] **Step 3: Create a real migration for the cable schema**

`db/cable_schema.rb` is an `ActiveRecord::Schema.define` schema dump, **not** a
migration class — it cannot be copied into `db/cable_migrate` and run by
`db:migrate`. Write a proper migration instead:

```bash
mkdir -p db/cable_migrate
```

```ruby
# db/cable_migrate/001_create_solid_cable_messages.rb
class CreateSolidCableMessages < ActiveRecord::Migration[7.2]
  def change
    create_table :solid_cable_messages do |t|
      t.binary :channel, limit: 1024, null: false
      t.binary :payload, limit: 536_870_912, null: false
      t.datetime :created_at, null: false
      t.integer :channel_hash, limit: 8, null: false
      t.index :channel
      t.index :channel_hash
      t.index :created_at
    end
  end
end
```

- [ ] **Step 4: Create and migrate the dev cable database**

```bash
mise exec -- bin/rails db:prepare
```

Expected: the primary DB is untouched and the cable DB gets exactly one table.
Verify both:

```bash
mise exec -- bin/rails runner 'ActiveRecord::Base.establish_connection(:cable); puts ActiveRecord::Base.connection.tables.sort.inspect'
mise exec -- bin/rails runner 'ActiveRecord::Base.establish_connection(:cable); puts ActiveRecord::Base.connection.table_exists?("solid_cable_messages")'
```

Expected: first prints `["ar_internal_metadata", "schema_migrations", "solid_cable_messages"]`;
second prints `true`. If the first output includes domain tables (`assets`,
`vec0_*`, etc.), the `database.yml` block is wrong — re-check Step 1.

- [ ] **Step 5: Verify the web app still boots and the adapter loads**

```bash
mise exec -- bin/rails runner 'puts ActionCable.server.config.cable[:adapter]'
```

Expected: `solid_cable`.

- [ ] **Step 6: Commit**

```bash
git add config/database.yml config/cable.yml db/cable_migrate
git commit -q -m "feat: use solid cable in development for cross-process streams"
```

---

### Task 9: Job broadcasts and stream-renderable partials

**Files:**
- Modify: `app/models/job.rb`
- Create: `app/views/jobs/_job.html.erb`
- Replace: `app/views/jobs/index.html.erb`
- Modify: `app/jobs/import_job.rb`
- Modify: `app/jobs/cluster_faces_job.rb`
- Create: `app/services/face_enrichment.rb`
- Create: `app/views/persons/_review_queue.html.erb`
- Create: `test/services/job_stream_test.rb`

- [ ] **Step 1: Broadcast from the domain Job model**

```ruby
# app/models/job.rb — add include at the top of the class, and the callbacks inside it
class Job < ApplicationRecord
  include Turbo::Broadcastable

  after_create_commit  { broadcast_prepend_later_to "jobs", target: "jobs_list", partial: "jobs/job", locals: { job: self } }
  after_update_commit  { broadcast_replace_later_to "jobs", target: "job_#{id}", partial: "jobs/job", locals: { job: self } }
```

`broadcast_prepend_later_to` / `broadcast_replace_later_to` are defined in the
`Turbo::Broadcastable` concern, so the model must `include Turbo::Broadcastable`
first — without it these methods do not exist on `Job`.

This pushes each create/update (`queued` → `working` → progress → `done`/`error`)
to every page subscribed to the `"jobs"` stream — no polling.

- [ ] **Step 2: Write the job card partial**

```erb
<%# app/views/jobs/_job.html.erb %>
<div class="card" id="job_<%= job.id %>">
  <strong>#<%= job.id %> · <%= job.kind %></strong>
  <span class="muted"><%= job.status %> · <%= (job.progress.to_f * 100).round %>%</span>
  <% if job.error %><p class="status"><%= job.error %></p><% end %>
</div>
```

- [ ] **Step 3: Replace the jobs page to subscribe and render the partials**

```erb
<%# app/views/jobs/index.html.erb %>
<% content_for :title, "Jobs" %>
<h1>Jobs</h1>
<%= turbo_stream_from "jobs" %>
<div class="cards" id="jobs_list">
  <% @jobs.each do |job| %>
    <%= render partial: "jobs/job", locals: { job: job } %>
  <% end %>
</div>
<% if @jobs.empty? %><p class="muted">No jobs yet.</p><% end %>
```

- [ ] **Step 4: Broadcast the catalog overview after an import**

```ruby
# app/jobs/import_job.rb — replace the whole file
require "fileutils"

class ImportJob < ApplicationJob
  queue_as :default

  def perform(job_id:, path:, index:, total:)
    job = Job.find(job_id)
    AssetImporter.import(path)
    job.record_completion!(total)
    broadcast_catalog if job.reload.status == "done"
  rescue StandardError => e
    FileUtils.rm_f(path) if job&.kind == "import"
    job&.fail!(e.message)
    broadcast_catalog if job&.reload&.status == "error"
  end

  private

  def broadcast_catalog
    Turbo::StreamsChannel.broadcast_replace_later_to "catalog",
      target: "catalog_overview",
      partial: "catalog/overview",
      locals: { overview: CatalogOverview.call }
  end
end
```

The catalog overview refreshes once the import job reaches `done` (or `error`
after a failure), so the funnel and recent-imports rows update without a page
reload. `record_completion!` already guards against overwriting a finished job,
so only the terminal state triggers the broadcast.

- [ ] **Step 5: Extract face enrichment to a service, then broadcast the people review queue after clustering**

Create a small service so both `ClusterFacesJob` and `PersonsController` share
the same enrichment data:

```ruby
# app/services/face_enrichment.rb
class FaceEnrichment
  def self.call
    total = Face.count
    ready = FaceEmbed.count
    run = ClusteringRun.order(id: :desc).first
    {
      total: total,
      embeddings_ready: ready,
      embeddings_pending: [ total - ready, 0 ].max,
      assets_processing: Asset.not_deleted.where.missing(:content_embed).count,
      clustering_status: clustering_status(total, run)
    }
  end

  def self.clustering_status(total, run)
    return "no_faces" if total.zero?
    return "ready" if run.nil?
    %w[running queued].include?(run.status) ? run.status : "ready"
  end
end
```

```ruby
# app/jobs/cluster_faces_job.rb — replace perform with the broadcast after the run
  def perform(job_id: nil, eps: FaceClustering::DEFAULT_EPS, min_samples: FaceClustering::DEFAULT_MIN_SAMPLES)
    job = job_id && Job.find(job_id)
    FaceClustering.run(eps: eps, min_samples: min_samples, job: job)
    Turbo::StreamsChannel.broadcast_replace_later_to "people",
      target: "review_queue",
      partial: "persons/review_queue",
      locals: {
        suggestions: ClusterSuggestion.includes(:representative_face, :face_assignments).order(:id),
        enrichment: FaceEnrichment.call
      }
  end
```

The `FaceEnrichment` service replaces the `face_enrichment`/`clustering_status`
private methods that Task 10 Step 3 would otherwise add to `PersonsController` —
use `FaceEnrichment.call` there instead. The `"people"` broadcast fires after
every clustering run, so the review queue and enrichment card update in place
without a reload.

- [ ] **Step 6: Write the review queue partial**

```erb
<%# app/views/persons/_review_queue.html.erb %>
<% show_rejected = local_assigns[:show_rejected] %>
<div id="review_queue">
  <% visible = suggestions.select { |s| s.status == "unreviewed" || (show_rejected && s.status == "rejected") } %>
  <% if visible.any? %>
    <%= render partial: "persons/suggestion", collection: visible, as: :suggestion %>
  <% else %>
    <p class="muted">No unreviewed clusters yet.</p>
  <% end %>
</div>
```

The partial reads `show_rejected` via `local_assigns` so it works both when the
page renders it (passing `show_rejected: @show_rejected`) and when the `"people"`
stream broadcast re-renders it (no `show_rejected`, so unreviewed suggestions
only).

- [ ] **Step 7: Write the stream test**

`broadcast_*_later_to` enqueues a `Turbo::Streams::ActionBroadcastJob`, so the
test asserts on enqueued jobs (Solid Queue's test adapter records them), not on
`Turbo::StreamsChannel.broadcasts`, which does not exist in turbo-rails 2.0.23.

```ruby
# test/services/job_stream_test.rb
require "test_helper"

class JobStreamTest < ActiveSupport::TestCase
  test "job updates enqueue a broadcast to the jobs stream" do
    assert_enqueued_with(job: Turbo::Streams::ActionBroadcastJob) do
      job = Job.create!(kind: "scan")
      job.update!(status: "working", progress: 0.5)
    end
  end

  test "import job completion broadcasts the catalog overview" do
    job = Job.create!(kind: "import")
    path = Rails.root.join("test/fixtures/tiny.jpg").to_s
    assert_enqueued_with(job: Turbo::Streams::ActionBroadcastJob) do
      ImportJob.perform_now(job_id: job.id, path: path, index: 0, total: 1)
    end
  end
end
```

If `assert_enqueued_with` with a job-class argument is awkward with this Solid
Queue adapter, fall back to a different, still-specific assertion: count rows in
the `solid_cable_messages` table before/after (Solid Cable persists broadcasts
there) and assert the count grew by at least one.

- [ ] **Step 8: Verify**

```bash
mise exec -- bin/rails test test/services/job_stream_test.rb
```

Expected: both tests green. If `ImportJob` requires the sidecar for the fixture
import, stub `SidecarClient` in the test (see Phase 2 `face_detection_test.rb`
for the pattern) or assert only the job-creation broadcast.

- [ ] **Step 9: Commit**

```bash
git add app/models/job.rb app/views/jobs/_job.html.erb app/views/jobs/index.html.erb app/jobs/import_job.rb app/jobs/cluster_faces_job.rb app/services/face_enrichment.rb app/views/persons/_review_queue.html.erb test/services/job_stream_test.rb
git commit -q -m "feat: broadcast job progress and catalog/people updates via turbo streams"
```

---

### Task 10: Person and suggestion JSON shape

**Files:**
- Modify: `app/models/person.rb`
- Modify: `app/models/cluster_suggestion.rb`
- Modify: `app/controllers/persons_controller.rb`
- Modify: `app/controllers/person_suggestions_controller.rb`
- Create: `app/views/persons/index.json.jbuilder`
- Create: `app/views/persons/search.json.jbuilder`
- Create: `test/controllers/persons_json_test.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Add Person helpers**

```ruby
# app/models/person.rb — add inside class Person
  def face_count
    person_faces.count
  end

  def representative_url
    face_id = prototype_face_id || faces.first&.id
    face_id && "/persons/faces/#{face_id}/crop"
  end
```

- [ ] **Step 2: Add ClusterSuggestion helpers**

```ruby
# app/models/cluster_suggestion.rb — add inside class ClusterSuggestion
  def face_count
    face_assignments.count
  end

  def representative_url
    representative_face_id && "/persons/faces/#{representative_face_id}/crop"
  end
```

- [ ] **Step 3: Extend PersonsController**

```ruby
# app/controllers/persons_controller.rb
class PersonsController < ApplicationController
  def index
    @persons = Person.search(params[:q]).includes(:aliases, :faces).order(:name)
    @suggestions = ClusterSuggestion.includes(:representative_face, :face_assignments).order(:id)
    @show_rejected = params[:show_rejected] == "1"
    @enrichment = FaceEnrichment.call
    respond_to do |format|
      format.html
      format.json
    end
  end

  def search
    @persons = Person.search(params[:q]).includes(:aliases, :faces).order(:name).limit(20)
    render json: { persons: @persons.as_json(include: :aliases) }
  end

  def update
    person = Person.find(params[:id])
    person.update!(person_params)
    render_person(person)
  end

  def cluster
    job = Job.create!(kind: "cluster", status: "queued", params: {})
    ClusterFacesJob.perform_later(job_id: job.id)
    respond_to { |format| format.json { render json: job, status: :accepted }; format.html { redirect_to persons_path } }
  end

  private

  def person_params
    params.require(:person).permit(:name)
  end

  def render_person(person)
    respond_to { |format| format.json { render json: person }; format.html { redirect_to persons_path } }
  end
end
```

> `@enrichment` is set from the shared `FaceEnrichment.call` service (created in
> Task 9 Step 5) — there are **no** `face_enrichment`/`clustering_status` private
> methods here; both this controller and `ClusterFacesJob` call the service.

- [ ] **Step 4: Allow confirm-by-name**

```ruby
# app/controllers/person_suggestions_controller.rb — replace the confirm action
  def confirm
    person = Person.find_by(id: params[:person_id]) ||
             (params[:name].present? ? Person.create!(name: params[:name]) : nil)
    @suggestion.confirm!(person: person)
    render_result
  end
```

- [ ] **Step 5: Write the index jbuilder**

```ruby
# app/views/persons/index.json.jbuilder
json.persons @persons do |person|
  json.extract! person, :id, :name, :status, :prototype_face_id
  json.face_count person.face_count
  json.representative_url person.representative_url
  json.aliases person.aliases do |alias_record|
    json.extract! alias_record, :id, :alias
  end
end

json.suggestions @suggestions do |suggestion|
  json.extract! suggestion, :id, :run_id, :confidence, :status, :person_id
  json.face_count suggestion.face_count
  json.representative_url suggestion.representative_url
  json.faces suggestion.face_assignments do |assignment|
    json.face_id assignment.face_id
    json.distance assignment.distance
    json.crop_url assignment.face&.crop_path ? "/persons/faces/#{assignment.face_id}/crop" : nil
  end
end

json.enrichment @enrichment
```

- [ ] **Step 6: Write the search jbuilder**

```ruby
# app/views/persons/search.json.jbuilder
json.persons @persons do |person|
  json.extract! person, :id, :name, :status
  json.face_count person.face_count
  json.representative_url person.representative_url
  json.aliases person.aliases do |alias_record|
    json.extract! alias_record, :id, :alias
  end
end
```

- [ ] **Step 7: Point the search route at the new action**

```ruby
# config/routes.rb — replace the existing line
  get "/persons/search", to: "persons#search"
```

- [ ] **Step 8: Write the JSON shape tests**

```ruby
# test/controllers/persons_json_test.rb
require "test_helper"

class PersonsJsonTest < ActionDispatch::IntegrationTest
  setup do
    @asset = Asset.create!(path: Rails.root.join("test/fixtures/tiny.jpg"), sha256: "json-test", size_bytes: 1, mime: "image/jpeg")
    @person = Person.create!(name: "Sam")
  end

  test "index returns persons, suggestions, and enrichment" do
    get "/persons", headers: { "ACCEPT" => "application/json" }
    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("persons")
    assert body.key?("suggestions")
    assert body.key?("enrichment")
  end

  test "search returns matching persons" do
    get "/persons/search?q=Sam", headers: { "ACCEPT" => "application/json" }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["persons"].length
    assert_equal "Sam", body["persons"].first["name"]
  end

  test "confirms a suggestion with a name" do
    face = Face.create!(asset: @asset, bbox: "0,0,1,1", crop_path: "missing.jpg")
    run = ClusteringRun.create!(model: "m", model_version: "v", algorithm: "dbscan", metric: "cosine", eps: 0.35, min_samples: 2)
    suggestion = ClusterSuggestion.create!(run: run, cluster_key: 1, face_count: 1, confidence: "high")
    FaceAssignment.create!(run: run, face: face, suggestion: suggestion, status: "suggested")

    post "/persons/suggestions/#{suggestion.id}/confirm",
      params: { name: "Sam" }, headers: { "ACCEPT" => "application/json" }

    assert_response :success
    assert_equal "Sam", suggestion.reload.person.name
  end

  test "index includes rejected suggestions and filters for html" do
    run = ClusteringRun.create!(model: "m", model_version: "v", algorithm: "dbscan", metric: "cosine", eps: 0.35, min_samples: 2)
    rejected = ClusterSuggestion.create!(run: run, cluster_key: 2, face_count: 1, confidence: "candidate", status: "rejected")

    get "/persons", headers: { "ACCEPT" => "application/json" }
    body = JSON.parse(response.body)
    assert_equal [ "rejected" ], body["suggestions"].map { |s| s["status"] }

    get "/persons"
    assert_response :success
    assert_no_match /Review again/, response.body

    get "/persons?show_rejected=1"
    assert_response :success
    assert_match /Review again/, response.body

    post "/persons/suggestions/#{rejected.id}/restore", headers: { "ACCEPT" => "application/json" }
    assert_response :success
    assert_equal "unreviewed", rejected.reload.status
  end
end
```

- [ ] **Step 9: Verify**

```bash
mise exec -- bin/rails test test/controllers/persons_json_test.rb test/models/cluster_suggestion_test.rb test/models/source_test.rb
```

Expected: all green (the `cluster_suggestion_test` exercises `confirm!` with the
new Person helpers).

- [ ] **Step 10: Commit**

```bash
git add app/models/person.rb app/models/cluster_suggestion.rb app/controllers/persons_controller.rb app/controllers/person_suggestions_controller.rb app/views/persons/index.json.jbuilder app/views/persons/search.json.jbuilder test/controllers/persons_json_test.rb config/routes.rb
git commit -q -m "feat: persons json contract with enrichment and picker search"
```

---

### Task 11: Stimulus controllers

**Files:**
- Create: `app/javascript/controllers/tabs_controller.js`
- Create: `app/javascript/controllers/funnel_controller.js`
- Create: `app/javascript/controllers/thumbnail_fallback_controller.js`
- Create: `app/javascript/controllers/person_picker_controller.js`

These are auto-registered by `app/javascript/controllers/index.js` (eager
load). No route or import changes needed.

- [ ] **Step 1: Tabs controller**

```javascript
// app/javascript/controllers/tabs_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "tab", "panel" ]

  select(event) {
    const key = event.currentTarget.dataset.tabKey
    this.tabTargets.forEach((tab) => {
      tab.setAttribute("aria-selected", tab.dataset.tabKey === key ? "true" : "false")
    })
    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.panelKey !== key
    })
  }
}
```

- [ ] **Step 2: Funnel controller**

```javascript
// app/javascript/controllers/funnel_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "stage", "panel" ]

  toggle(event) {
    const key = event.currentTarget.dataset.stageKey
    const wasPressed = event.currentTarget.getAttribute("aria-pressed") === "true"
    this.stageTargets.forEach((stage) => stage.setAttribute("aria-pressed", "false"))
    if (!wasPressed) event.currentTarget.setAttribute("aria-pressed", "true")
    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.stagePanel !== key || wasPressed
    })
  }
}
```

- [ ] **Step 3: Thumbnail fallback controller**

```javascript
// app/javascript/controllers/thumbnail_fallback_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "image", "fallback" ]

  failed() {
    this.imageTarget.hidden = true
    this.fallbackTarget.hidden = false
  }
}
```

- [ ] **Step 4: Person picker controller**

```javascript
// app/javascript/controllers/person_picker_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "query", "results", "selection", "summary" ]
  static values = { exclude: Number }

  search() {
    this.clearTimer()
    const query = this.queryTarget.value.trim()
    if (!query) { this.resultsTarget.replaceChildren(); return }
    this.timer = setTimeout(() => {
      fetch(`/persons/search?q=${encodeURIComponent(query)}`, { headers: { Accept: "application/json" } })
        .then((response) => response.json())
        .then((data) => {
          const matches = data.persons.filter((person) => person.id !== this.excludeValue)
          this.resultsTarget.replaceChildren(...matches.map((person) => {
            const button = document.createElement("button")
            button.type = "button"
            button.className = "pickerResult"
            button.innerHTML = `<span class="personSummary"><span>${person.name || "Unnamed person"}</span></span><span>${person.face_count} faces</span>`
            button.addEventListener("click", () => this.select(person))
            return button
          }))
        })
        .catch(() => this.resultsTarget.replaceChildren())
    }, 250)
  }

  select(person) {
    this.selectionTarget.value = person.id
    if (this.element.dataset.personPickerMergeUrl) {
      this.element.action = this.element.dataset.personPickerMergeUrl.replace(/\/\d+$/, `/${person.id}`)
    }
    if (this.hasSummaryTarget) {
      this.summaryTarget.textContent = `${person.name || "Unnamed person"} · ${person.face_count} faces`
    }
    this.resultsTarget.replaceChildren()
    this.queryTarget.value = ""
  }

  clearTimer() {
    if (this.timer) { clearTimeout(this.timer); this.timer = null }
  }

  disconnect() {
    this.clearTimer()
  }
}
```

- [ ] **Step 5: Verify the controllers load**

Run: `mise exec -- bin/rails runner 'puts Rails.application.importmap.resolved_paths("controllers").length'`
Expected: a number (import map intact), and no load errors when hitting any page
from Task 4/7 that references these controllers. Browser-level behavior is
verified manually in Task 16.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers
git commit -q -m "feat: stimulus controllers for tabs, funnel, thumbnails, picker"
```

---

### Task 12: People page views (tabs + enrichment + suggestion/person cards)

**Files:**
- Replace: `app/views/persons/index.html.erb`
- Replace: `app/views/persons/_suggestion.html.erb`
- Replace: `app/views/persons/_person.html.erb`
- Create: `app/views/persons/_person_picker.html.erb`

- [ ] **Step 1: Replace the index view**

```erb
<%# app/views/persons/index.html.erb %>
<% content_for :title, "People" %>
<%= turbo_stream_from "people" %>
<%= turbo_stream_from "catalog" %>
<p class="eyebrow">Identity review</p>
<h1>People</h1>
<p class="lead">Clusters are suggestions, not identities. Confirm only the groups that look right; your decisions survive future clustering runs.</p>

<div class="card enrichmentCard">
  <strong>Face enrichment</strong>
  <span class="muted"><%= people_enrichment_message(@enrichment) %></span>
  <span class="muted"><%= number_with_delimiter(@enrichment[:embeddings_ready]) %> embeddings ready · <%= number_with_delimiter(@enrichment[:embeddings_pending]) %> pending</span>
</div>

<div data-controller="tabs">
  <div class="tabs">
    <button type="button" class="tab" data-tabs-target="tab" data-tab-key="suggestions" aria-selected="true" data-action="click->tabs#select">Suggestions</button>
    <button type="button" class="tab" data-tabs-target="tab" data-tab-key="people" aria-selected="false" data-action="click->tabs#select">Named People</button>
  </div>

  <section data-tabs-target="panel" data-panel-key="suggestions">
    <h2>Review queue</h2>
    <%= button_to "Run clustering", "/persons/cluster", method: :post, class: "button" %>
    <%= form_with url: persons_path, method: :get, local: true do |form| %>
      <label>
        <%= form.check_box :show_rejected, checked: @show_rejected, onchange: "this.form.submit()" %>
        Show rejected suggestions
      </label>
    <% end %>
    <%= render "persons/review_queue", suggestions: @suggestions, show_rejected: @show_rejected %>
  </section>

  <section data-tabs-target="panel" data-panel-key="people" hidden>
    <h2>People</h2>
    <div id="people">
      <% if @persons.any? %>
        <%= render partial: "person", collection: @persons, as: :person %>
      <% else %>
        <p class="muted">No people have been identified yet.</p>
      <% end %>
    </div>
  </section>
</div>
```

- [ ] **Step 2: Add the enrichment message helper**

```ruby
# app/helpers/application_helper.rb — add inside module ApplicationHelper
  def people_enrichment_message(enrichment)
    status = enrichment[:clustering_status]
    return "No faces have been indexed yet." if status == "no_faces"
    if status == "indexing"
      "Face indexing in progress. Run clustering again when it finishes."
    elsif enrichment[:assets_processing] > 0
      "Some assets are still processing. Run clustering again when processing finishes."
    elsif %w[queued running].include?(status)
      "Clustering is in progress. Suggestions will appear when the worker finishes."
    elsif status == "completed_no_suggestions"
      "Clustering completed without finding new groups."
    else
      "Face indexing is complete. Clustering is ready."
    end
  end
```

- [ ] **Step 3: Replace the suggestion card**

```erb
<%# app/views/persons/_suggestion.html.erb %>
<article id="suggestion_<%= suggestion.id %>" class="card">
  <strong><%= suggestion.confidence %> · <%= pluralize(suggestion.face_count, "face") %></strong>
  <% if suggestion.status == "rejected" %><span class="muted">Rejected</span><% end %>
  <div class="faceRow">
    <% suggestion.face_assignments.each do |assignment| %>
      <% if assignment.face&.crop_path.present? %>
        <img src="/persons/faces/<%= assignment.face.id %>/crop" alt="Face suggestion">
      <% end %>
    <% end %>
  </div>

  <% if suggestion.status == "rejected" %>
    <%= button_to "Review again", restore_person_suggestion_path(suggestion), method: :post, class: "button" %>
  <% else %>
    <%= form_with url: confirm_person_suggestion_path(suggestion), method: :post, data: { controller: "person-picker" } do |form| %>
      <%= hidden_field_tag "person_id", nil, data: { person_picker_target: "selection" } %>
      <%= form.text_field :name, name: "name", placeholder: "Name this person", class: "searchInput" %>
      <%= render "person_picker", form: form %>
      <p class="muted" data-person-picker-target="summary"></p>
      <div style="display:flex; gap:8px; margin-top:10px">
        <%= form.submit "Confirm", class: "button" %>
        <%= button_to "Reject", reject_person_suggestion_path(suggestion), method: :post, class: "button secondary", form_class: "" %>
      </div>
    <% end %>
  <% end %>
</article>
```

> Route names used: `confirm_person_suggestion_path`, `reject_person_suggestion_path`,
> `restore_person_suggestion_path` — add the `as:` names in Task 11 Step 1.

- [ ] **Step 4: Write the person picker partial**

```erb
<%# app/views/persons/_person_picker.html.erb %>
<%= form.search_field :picker_query, name: "picker_query", placeholder: "Search existing people", class: "searchInput", "aria-label": "Search existing people", data: { person_picker_target: "query", action: "input->person-picker#search" } %>
<div class="pickerResults" data-person-picker-target="results"></div>
```

- [ ] **Step 5: Replace the person card**

```erb
<%# app/views/persons/_person.html.erb %>
<article id="person_<%= person.id %>" class="card personCard">
  <div class="personSummary">
    <% if person.representative_url %>
      <img src="<%= person.representative_url %>" alt="<%= person.name.presence || "Unnamed person" %> representative">
    <% else %>
      <div class="personPlaceholder">?</div>
    <% end %>
    <span><%= person.name.presence || "Unnamed person" %></span>
    <% if person.aliases.any? %>
      <small><%= person.aliases.map(&:alias).join(", ") %></small>
    <% end %>
  </div>
  <strong><%= pluralize(person.face_count, "face") %></strong>

  <%= form_with model: person, url: person_path(person), method: :patch, class: "aliasRow" do |form| %>
    <%= form.text_field :name, value: person.name, class: "searchInput", placeholder: "Name this person" %>
    <%= form.submit "Save name", class: "button" %>
  <% end %>

  <div class="aliasList">
    <% person.aliases.each do |person_alias| %>
      <span class="aliasChip"><%= person_alias.alias %><%= button_to "×", person_person_alias_path(person, person_alias), method: :delete, aria: { label: "Remove alias #{person_alias.alias}" } %></span>
    <% end %>
  </div>
  <%= form_with url: person_person_aliases_path(person), method: :post, class: "aliasRow" do |form| %>
    <%= form.text_field :alias, name: "person_alias[alias]", placeholder: "Add an alias", class: "searchInput" %>
    <%= form.submit "Add alias", class: "button secondary" %>
  <% end %>

  <div class="mergePanel">
    <strong>Merge with another person</strong>
    <%= form_with url: merge_person_path(person, 0), method: :post, data: { controller: "person-picker", person_picker_merge_url: merge_person_path(person, 0) } do |form| %>
      <%= hidden_field_tag "remove_id", nil, data: { person_picker_target: "selection" } %>
      <%= render "person_picker", form: form %>
      <p class="muted" data-person-picker-target="summary"></p>
      <%= form.submit "Merge into this person", class: "button" %>
    <% end %>
  </div>

  <details class="setupDetails">
    <summary>Split faces into a new person</summary>
    <%= form_with url: split_person_path(person), method: :post do |form| %>
      <div class="faceRow">
        <% person.faces.each do |face| %>
          <% if face.crop_path.present? %>
            <label><%= check_box_tag "face_ids[]", face.id %><%= image_tag "/persons/faces/#{face.id}/crop", alt: "Face #{face.id}" %></label>
          <% end %>
        <% end %>
      </div>
      <%= form.text_field :name, name: "person[name]", placeholder: "New person name", class: "searchInput" %>
      <%= form.submit "Split selected faces", class: "button secondary" %>
    <% end %>
  </details>
</article>
```

- [ ] **Step 6: Verify**

```bash
mise exec -- bin/rails test test/controllers/person_mutations_controller_test.rb test/controllers/persons_json_test.rb
mise exec -- bin/rails runner 'puts ApplicationController.view_paths.first.to_a.map(&:path).first'
```

Expected: mutation + JSON tests green. Then a manual render smoke check:

```bash
mise exec -- bin/rails server &
sleep 8
curl -s -H 'Accept: text/html' http://localhost:3000/persons | grep -o "Review queue"
kill %1 2>/dev/null
```

Expected: grep prints `Review queue`.

- [ ] **Step 7: Commit**

```bash
git add app/views/persons app/helpers/application_helper.rb
git commit -q -m "feat: people review page with tabs, picker, merge, and split"
```

---

### Task 13: Route names for suggestion actions

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Add named routes for suggestion confirm/reject/restore**

```ruby
# config/routes.rb — replace the three suggestion lines with named routes
  post "/persons/suggestions/:id/confirm", to: "person_suggestions#confirm", as: :confirm_person_suggestion
  post "/persons/suggestions/:id/reject", to: "person_suggestions#reject", as: :reject_person_suggestion
  post "/persons/suggestions/:id/restore", to: "person_suggestions#restore", as: :restore_person_suggestion
```

- [ ] **Step 2: Verify routes load**

Run: `mise exec -- bin/rails routes | grep "person_suggestion"`
Expected: three named routes for confirm/reject/restore.

- [ ] **Step 3: Commit**

```bash
git add config/routes.rb
git commit -q -m "feat: named routes for suggestion actions"
```

---

### Task 14: Settings page (admin status HTML + disk)

**Files:**
- Modify: `app/controllers/admin_controller.rb`
- Create: `app/views/admin/status.html.erb`
- Modify: `config/routes.rb`
- Create: `test/controllers/settings_controller_test.rb`

- [ ] **Step 1: Add disk + jobs + HTML to the status action**

```ruby
# app/controllers/admin_controller.rb
class AdminController < ApplicationController
  def status
    models_ready = SidecarClient.status["ok"] == true rescue false
    root_available = File.directory?(PICS_WATCH_ROOT)
    counts = {
      "assets" => Asset.count,
      "faces" => Face.count,
      "persons" => Person.count,
      "jobs" => Job.count
    }
    @status = {
      mount_source: ENV.fetch("PICS_MOUNT_SOURCE", nil),
      watch_root: PICS_WATCH_ROOT,
      root_available: root_available,
      models_ready: models_ready,
      disk: disk,
      counts: counts,
      settings: Setting.all_map
    }
    @jobs = Job.order(id: :desc).limit(20)
    respond_to do |format|
      format.html
      format.json { render json: @status.merge(jobs: @jobs.as_json(only: [ :id, :kind, :status, :progress, :error ])) }
    end
  end

  def settings
    render json: { settings: Setting.all_map }
  end

  def update_settings
    if params[:watch_enabled].present?
      Setting.set_value("watch_enabled", params[:watch_enabled]) if %w[0 1].include?(params[:watch_enabled].to_s)
    end
    if params[:watch_backfill].present?
      Setting.set_value("watch_backfill", params[:watch_backfill]) if %w[prompt backfill done].include?(params[:watch_backfill].to_s)
    end
    render json: { settings: Setting.all_map }
  end

  def scan
    root = PICS_WATCH_ROOT
    raise ActiveRecord::RecordNotFound, "root is not a directory: #{root}" unless File.directory?(root)

    paths = Dir.glob(File.join(root, "**", "*")).select do |path|
      File.file?(path) && MEDIA_SUFFIXES.include?(File.extname(path).downcase)
    end
    job = Job.create!(kind: "scan", params: { paths: paths }.to_json)
    ScanJob.perform_later(job_id: job.id, root: root)
    render json: { job_id: job.id, paths: paths.length, status: "queued" }
  end

  private

  def disk
    require "shellwords"
    output = `df -kP #{Shellwords.escape(PICS_LIBRARY)}`
    return nil unless output.lines.length >= 2
    fields = output.lines.last.split
    return nil unless fields.length >= 4
    { total: fields[1].to_i * 1024, used: fields[2].to_i * 1024, free: fields[3].to_i * 1024 }
  end
end
```

- [ ] **Step 2: Write the settings view**

```erb
<%# app/views/admin/status.html.erb %>
<% content_for :title, "Settings" %>
<p class="eyebrow">Operations</p>
<h1>Admin</h1>
<p class="lead">The app starts parked. Nothing watches or processes the mounted library until you enable it here.</p>

<h2>Watch &amp; ingest</h2>
<div class="cards">
  <div class="card">
    <strong>Mounted directory</strong>
    <div class="mountPaths">
      <p><span class="mountLabel">Host source</span><code><%= @status[:mount_source] || "Source not reported" %></code></p>
      <p><span class="mountLabel">App sees</span><code><%= @status[:watch_root] %></code></p>
    </div>
    <p class="mountState"><%= @status[:root_available] ? "Available to the app" : "Not available to the app" %></p>
    <p class="hint">The host folder is mounted read-only. Change it with <code>PICS_MOUNT_SOURCE</code> in Docker Compose, then restart Docker.</p>
  </div>

  <div class="card actionCard">
    <strong>Continuous watch</strong>
    <p class="muted"><%= watch_enabled? ? "Enabled" : "Paused" %></p>
    <%= form_with url: "/admin/settings", method: :patch do |form| %>
      <%= hidden_field_tag "watch_enabled", watch_enabled? ? "0" : "1" %>
      <%= form.submit watch_enabled? ? "Pause watch" : "Enable watch", class: "button cardAction" %>
    <% end %>
  </div>

  <div class="card actionCard">
    <strong>Library scan</strong>
    <p class="muted">Import all existing media immediately, without enabling continuous watch.</p>
    <%= button_to "Scan library now", "/admin/scan", method: :post, class: "button cardAction" %>
  </div>

  <div class="card actionCard">
    <strong>Import a photo</strong>
    <p class="muted">Upload an image directly into the library.</p>
    <%= link_to "Upload photo", "/assets/upload", class: "button cardAction" %>
  </div>
</div>

<h2>Clustering</h2>
<%= button_to "Run clustering", "/persons/cluster", method: :post, class: "button" %>

<h2>Jobs</h2>
<%= turbo_stream_from "jobs" %>
<div class="cards" id="jobs_list">
  <% @jobs.each do |job| %>
    <%= render partial: "jobs/job", locals: { job: job } %>
  <% end %>
</div>
<% if @jobs.empty? %><p class="muted">No jobs yet.</p><% end %>

<h2>Status</h2>
<div class="cards">
  <div class="card">
    <strong>Catalog</strong>
    <span class="muted"><%= @status[:counts]["assets"] %> assets · <%= @status[:counts]["faces"] %> faces · <%= @status[:counts]["persons"] %> people</span>
  </div>
  <div class="card">
    <strong>Models</strong>
    <span class="muted"><%= @status[:models_ready] ? "Ready" : "Loading" %></span>
  </div>
  <% if @status[:disk] %>
    <div class="card">
      <strong>Disk</strong>
      <span class="muted"><%= number_to_human_size(@status[:disk][:free]) %> free</span>
    </div>
  <% end %>
</div>
```

- [ ] **Step 3: Add the watch helper**

```ruby
# app/helpers/application_helper.rb — add inside module ApplicationHelper
  def watch_enabled?
    @status.present? && @status[:settings].is_a?(Hash) && @status[:settings]["watch_enabled"] == "1"
  end
```

- [ ] **Step 4: Add the settings route**

```ruby
# config/routes.rb — add inside the routes.draw block
  get "/settings", to: "admin#status"
```

- [ ] **Step 5: Write the test**

```ruby
# test/controllers/settings_controller_test.rb
require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  test "renders settings html page" do
    get "/settings"
    assert_response :success
    assert_match "Watch &amp; ingest", response.body
  end

  test "status json includes counts and settings" do
    get "/admin/status", as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("counts")
    assert body.key?("settings")
    assert body.key?("jobs")
  end
end
```

- [ ] **Step 6: Verify**

```bash
mise exec -- bin/rails test test/controllers/settings_controller_test.rb test/controllers/admin_controller_test.rb
```

Expected: all green. If `admin_controller_test.rb` asserts the exact status JSON
keys or `disk: nil`, update its assertions to include the new keys.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/admin_controller.rb app/views/admin/status.html.erb app/helpers/application_helper.rb config/routes.rb test/controllers/settings_controller_test.rb
git commit -q -m "feat: settings page with watch, scan, jobs, and status"
```

---

### Task 15: Layout shell + nav

**Files:**
- Modify: `app/views/layouts/application.html.erb`

- [ ] **Step 1: Replace the layout body**

```erb
<%# app/views/layouts/application.html.erb — replace the <body>...</body> block %>
  <body>
    <div class="shell">
      <header class="topbar">
        <%= link_to "pics.", "/", class: "brand" %>
        <nav class="nav">
          <%= link_to "People", persons_path, aria: { current: controller_name == "persons" ? "page" : nil } %>
          <%= link_to "Places", "/places", aria: { current: controller_name == "places" ? "page" : nil } %>
          <%= link_to "Photos", "/catalog/overview", aria: { current: controller_name == "catalog" ? "page" : nil } %>
          <%= link_to "Settings", "/settings", aria: { current: controller_name == "admin" ? "page" : nil } %>
        </nav>
      </header>
      <% if notice %><p class="notice"><%= notice %></p><% end %>
      <% if alert %><p class="alert"><%= alert %></p><% end %>
      <main>
        <%= yield %>
      </main>
    </div>
  </body>
```

Live data is pushed via Turbo Streams (Task 9); the layout needs no polling or
morph attributes. Pages opt into streams with `<%= turbo_stream_from ... %>`
where they render shared partials (`jobs/_job`, `catalog/_overview`,
`persons/_review_queue`).

- [ ] **Step 2: Verify**

```bash
mise exec -- bin/rails test
```

Expected: full suite green (34 + new tests). Then check the layout renders the
nav on a page:

```bash
mise exec -- bin/rails server &
sleep 8
curl -s -H 'Accept: text/html' http://localhost:3000/ | grep -o "People"
kill %1 2>/dev/null
```

Expected: grep prints `People`.

- [ ] **Step 3: Commit**

```bash
git add app/views/layouts/application.html.erb
git commit -q -m "feat: app shell nav"
```

---

### Task 16: Quality gates + browser verification

**Files:**
- None (verification)

- [ ] **Step 1: Run the full suite**

```bash
mise exec -- bin/rails test
```

Expected: all green.

- [ ] **Step 2: Rubocop**

```bash
mise exec -- bin/rubocop app lib test
```

Expected: no offenses.

- [ ] **Step 3: Brakeman**

```bash
mise exec -- bin/brakeman --no-pager
```

Expected: no warnings.

- [ ] **Step 4: Manual browser pass against the stub sidecar**

Start the full stack (`docker compose up -d sidecar rails worker`) and confirm,
page by page. The compose file already defines the `worker` service (running
`bin/jobs start`) — no compose changes are needed for this plan.

1. `/` — hero renders, search with `a picnic who:Sam` returns results grid with
   thumbnails; a broken thumbnail shows "Preview pending".
2. `/catalog/overview` — funnel stages render; clicking a stage shows the
   per-source drilldown; context cards and recent imports render; source cards
   show badges.
3. `/persons` — tabs switch between Suggestions and Named People; the show-rejected toggle reveals rejected cards with "Review again" (restore); the picker searches people; confirm-with-name creates a person; merge and split work.
4. `/places` — cards list city/country/count.
5. `/settings` — mount paths, watch toggle, scan, clustering, jobs, status
   (disk free) render.
6. Live updates — with `/settings` and `/catalog/overview` open in two tabs,
   trigger `POST /admin/scan`: job cards appear/progress on `/settings` and the
   overview funnel counts update **without any page reload** (Turbo Streams
   push from the worker container over Solid Cable).

- [ ] **Step 5: Commit plan state**

```bash
git add artifacts/photo-searchable-library-rails/ui-parity/ui-parity-plan.md
git commit -q -m "chore: record ui parity plan"
```

---

## Verification Summary

After all tasks complete:

- [ ] `mise exec -- bin/rails test` — all tests pass (Phase 1/2/3)
- [ ] `mise exec -- bin/rubocop app lib test` — no offenses
- [ ] `mise exec -- bin/brakeman --no-pager` — no warnings
- [ ] `/` renders the search hero; structured filters (`who:`/`place:`/`before:`/`after:`/`tag:`) work
- [ ] `/catalog/overview` shows funnel + drilldown + context + recent imports + source cards
- [ ] `/persons` shows tabs, enrichment card, suggestion confirm/reject/restore, the show-rejected toggle, person rename/alias/merge/split, and a working person picker
- [ ] `/places` lists aggregated city/country counts
- [ ] `/settings` shows watch, scan, clustering, jobs, and status (with disk)
- [ ] Job progress appears on `/jobs` and `/settings` **without reloading** — a running scan/import updates the job cards via the `"jobs"` Turbo Stream
- [ ] Completing an import updates `/catalog/overview` funnel/recent-imports **without reloading** via the `"catalog"` stream; completing clustering updates `/persons` review queue via the `"people"` stream
- [ ] Solid Cable is the dev adapter; the Docker worker container broadcasts to the web container (`docker compose up -d rails worker` then watch jobs update)
- [ ] Apple Photos sync controls remain deferred (Phase 4)