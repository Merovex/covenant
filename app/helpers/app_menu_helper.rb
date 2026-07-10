# The app menu (jump-to sheet): its destinations and recent records. Kept small
# and server-rendered — the Stimulus controller only filters what's already here.
module AppMenuHelper
  # Only content with a standalone page belongs in the recents list.
  MENU_RECORDABLES = %w[ Post Message ].freeze

  # The most recently touched records the user can jump back to.
  def app_menu_recents(limit: 6)
    Record.recently_active.where(recordable_type: MENU_RECORDABLES).limit(limit)
  end

  # The lucide glyph that represents a recordable type.
  RECORDABLE_ICONS = {
    "Post" => "file-text", "Message" => "messages-square"
  }.freeze

  def app_menu_icon(recordable_type)
    RECORDABLE_ICONS[recordable_type]
  end

  # A quick-nav card (icon over label) for the grid at the top of the menu.
  def app_menu_card(label, href, icon)
    link_to href, class: "app-menu__card" do
      safe_join [
        inline_svg_tag("lucide/#{icon}.svg", class: "lucide app-menu__card-icon", size: "22px"),
        tag.span(label, class: "app-menu__card-label")
      ]
    end
  end

  # A single row: a link styled as a menu option, filterable by its text.
  def app_menu_link(label, href, kind: nil, icon: nil)
    link_to href, class: "app-menu__item", role: "option", tabindex: "-1",
      data: { app_menu_target: "item" } do
      safe_join [
        (inline_svg_tag("lucide/#{icon}.svg", class: "lucide app-menu__icon", size: "18px") if icon),
        tag.span(label, class: "app-menu__label"),
        (tag.span(kind, class: "app-menu__kind") if kind)
      ].compact
    end
  end

  def app_menu_record_path(record)
    case record.recordable_type
    when "Post"    then post_path(record)
    when "Message" then message_path(record)
    end
  end

  def app_menu_record_label(record)
    record.recordable&.title.presence || "Untitled"
  end
end
