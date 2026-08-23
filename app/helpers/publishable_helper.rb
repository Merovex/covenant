# View helpers shared by every publishable type's pages (posts, messages):
# the history feed lines and the counted drafts link. `noun` is how the type
# reads in a sentence ("post", "message").
module PublishableHelper
  # The history feed line for a version, derived from the delta against its
  # predecessor: the event tag narrates transitions; content and title changes
  # are detected by column comparison (body_id / title) — no rich text loads.
  def version_event_line(version, previous, noun:)
    return "created this #{noun}" if previous.nil?

    case version.event
    when "updated"
      if version.body_id == previous.body_id && version.title != previous.title
        %(changed the title of this #{noun} from “#{previous.title}” to “#{version.title}”)
      else
        "saved a new version of this #{noun}"
      end
    when "scheduled"   then "scheduled this #{noun} to publish #{version.published_at.strftime('%b %-d at %H:%M')}"
    when "unscheduled" then "unscheduled this #{noun}"
    when "published"   then "published this #{noun}"
    when "unpublished" then "reverted this #{noun} to a draft"
    when "pinned"      then "pinned this #{noun}"
    when "unpinned"    then "unpinned this #{noun}"
    when "trashed"     then "moved this #{noun} to the trash"
    when "restored"    then "restored this #{noun} from the trash"
    when "synced"      then "synced this #{noun} from Lemon Squeezy"
    else version.event
    end
  end

  # The counted link to unpublished work, worded by what exists.
  def unpublished_work_label(drafts_count, scheduled_count, noun:)
    if scheduled_count.positive? && drafts_count.positive?
      "Edit your #{pluralize(scheduled_count, "scheduled #{noun}")} and #{pluralize(drafts_count, 'draft')}…"
    elsif scheduled_count.positive?
      "Edit your #{pluralize(scheduled_count, "scheduled #{noun}")}"
    else
      "Edit your #{pluralize(drafts_count, 'draft')}…"
    end
  end

  def version_timestamp(version)
    version.created_at.strftime("%b %-d at %H:%M")
  end
end
