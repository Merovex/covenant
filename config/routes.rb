Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Dynamic PWA files from app/views/pwa/* (manifest is linked in the layout).
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Passwordless (magic-link) authentication.
  resource :session, only: %i[new create destroy]
  # Redeems the emailed code — hit by the magic link and the manual entry form.
  get "session/verify" => "sessions#verify", as: :verify_session

  # First-run install setup (first user → domain admin); only when no users exist.
  resource :setup, only: %i[new create]
  # Open self-registration; only when the registration policy is :open.
  resource :signup, only: %i[new create]

  # Living styleguide for building/eyeballing standard elements + components.
  get "theme" => "static#theme", as: :theme
  # Composition demos: a list-view (perma-header + list) and an item-view (editable header).
  get "list-view" => "static#list_view", as: :list_view
  get "item-view" => "static#item_view", as: :item_view

  # Defines the root path route ("/")
  # Temporary: point root at the styleguide until there's a real home page.
  root "static#theme"
end
