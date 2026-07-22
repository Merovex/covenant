# A single rich-text scratchpad for staff jottings, attached to a record and
# *not* versioned (unlike the spine's recordables). Mix into the stable identity:
# the Record (so a Ticket/License note survives status changes) or a plain model
# like Customer. Never customer-facing — internal notes only.
module Notable
  extend ActiveSupport::Concern

  included do
    has_rich_text :note
  end
end
