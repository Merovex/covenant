module ApplicationHelper
  # Icons are rendered with inline_svg_tag from real SVG files under
  # app/assets/images (e.g. app/assets/images/lucide/*.svg). Never hand-write
  # icon path data here.

  # Up-to-two-letter monogram for the avatar. Uses the user's name when set,
  # otherwise the first letters of their email address.
  def avatar_initials(user)
    source = user.name.presence || user.email_address
    source.scan(/[[:alpha:]]+/).first(2).map { |w| w[0] }.join.upcase
  end
end
