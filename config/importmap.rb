# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "lexxy", to: "lexxy.min.js"
# Downloads-by-country choropleth on /downloads (UMD globals — imported for
# side effect; the controller uses window.jsVectorMap).
pin "jsvectormap"
pin "jsvectormap-world"
