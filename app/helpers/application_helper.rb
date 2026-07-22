module ApplicationHelper
  # Icons are rendered with inline_svg_tag from real SVG files under
  # app/assets/images (e.g. app/assets/images/lucide/*.svg). Never hand-write
  # icon path data here.

  # What goes inside an .avatar: the uploaded picture when there is one,
  # otherwise the monogram.
  def avatar_content(user)
    if user.avatar.attached?
      image_tag user.avatar.variant(:thumb), alt: user.display_name, class: "avatar__img"
    else
      avatar_initials(user)
    end
  end

  # Up-to-two-letter monogram for the avatar.
  def avatar_initials(user)
    user.display_name.scan(/[[:alpha:]]+/).first(2).map { |w| w[0] }.join.upcase
  end

  # Where a ticket's "Tickets" breadcrumb returns: the last filter the agent
  # viewed (stored in the session by TicketsController#index), defaulting to the
  # Open queue on a first visit. "all" means the unfiltered index.
  def tickets_index_path
    filter = session[:tickets_filter].presence || "open"
    filter == "all" ? tickets_path : tickets_path(status: filter)
  end

  # The standard "who · when" line under list rows (comments, chat lines).
  def byline(creator, time, edited: false)
    tag.p class: "byline u-text-muted" do
      safe_join [
        tag.span(creator.display_name, class: "u-text-strong"),
        " · ",
        tag.time(time.strftime("%b %-d at %H:%M"), datetime: time.iso8601),
        (" · Edited" if edited)
      ].compact
    end
  end
end
