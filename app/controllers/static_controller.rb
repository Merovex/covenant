class StaticController < ApplicationController
  # Styleguide/demo pages sit behind sign-in like the rest of the app; the whole
  # site is authenticated (only the session/setup/signup flows are public).

  # Living styleguide. Renders every standard element/component so we can build
  # and eyeball HTML + CSS in isolation. See app/views/static/theme.html.erb.
  def theme
  end

  # Composition demo: a list index (perma-header toolbar + list of rows).
  def list_view
  end

  # Composition demo: a single item (editable perma-header title + content).
  def item_view
  end
end
