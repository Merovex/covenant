# One message in a ticket thread after the opener — inbound customer mail or
# outbound agent mail. A recordable (versioned) with an Action Text body,
# immutable like a comment. Its Record parents to the ticket's Record, so the
# spine threads it under the ticket.
class Reply < ApplicationRecord
  include Recordable

  # creator comes from Recordable (required — the parent Record needs one too).
  # Inbound mail has no human author, so the mailbox stamps User.system; the
  # column is left nullable only to keep a truly system-less row representable.
  has_rich_text :content

  enum :direction, %w[ inbound outbound ].index_by(&:itself)

  validates :direction, :from_address, :to_address, presence: true
  validates :content, presence: true

  def mutable? = false

  def build_successor(event:, creator:, **changes)
    super.tap do |version|
      version.content = content.body unless changes.key?(:content)
    end
  end

  # The ticket this reply belongs to — resolved through the spine (its Record's
  # parent is the ticket's Record).
  def ticket
    record&.parent&.recordable
  end
end
