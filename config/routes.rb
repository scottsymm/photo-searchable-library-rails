Rails.application.routes.draw do
  get "/", to: "health#index"
  get "/health", to: "health#index"
  get "/search", to: "search#index"
  get "/catalog/overview", to: "catalog#overview"
  get "/assets/upload", to: "uploads#new"
  post "/assets/upload", to: "uploads#create"
  get "/assets/:id/thumbnail", to: "assets#thumbnail"
  get "/jobs", to: "jobs#index"
  get "/jobs/:id", to: "jobs#show"
  get "/admin/status", to: "admin#status"
  get "/admin/settings", to: "admin#settings"
  patch "/admin/settings", to: "admin#update_settings"
  post "/admin/scan", to: "admin#scan"
  get "/persons/search", to: "persons#index"
  resources :persons, only: [ :index, :update ]
  post "/persons/:person_id/aliases", to: "person_aliases#create", as: :person_person_aliases
  delete "/persons/:person_id/aliases/:id", to: "person_aliases#destroy", as: :person_person_alias
  post "/persons/:person_id/faces/:face_id", to: "person_faces#create", as: :person_person_face
  post "/persons/:person_id/split", to: "person_merges#split", as: :split_person
  post "/persons/:person_id/merge/:remove_id", to: "person_merges#create", as: :merge_person
  post "/persons/cluster", to: "persons#cluster"
  post "/persons/suggestions/:id/confirm", to: "person_suggestions#confirm"
  post "/persons/suggestions/:id/reject", to: "person_suggestions#reject"
  post "/persons/suggestions/:id/restore", to: "person_suggestions#restore"
  get "/persons/faces/:face_id/crop", to: "person_faces#crop"

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
