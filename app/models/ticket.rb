# A support ticket — a recordable (versioned) whose opener is the customer's
# first email, carried as Action Text (has_rich_text :content) like a comment.
# Immutable: every status change / edit is a new version → free audit trail.
# Replies thread underneath via the spine (records.parent_id), exactly how
# comments hang off a post.
class Ticket < ApplicationRecord
  include Recordable

  belongs_to :customer
  has_rich_text :content              # the customer's opening email

  enum :status, %w[ open pending closed ].index_by(&:itself), default: :open

  validates :title, presence: true

  # Current versions of live tickets — mirrors Publishable#current.
  scope :current, -> { where(id: Record.active.where(recordable_type: "Ticket").select(:recordable_id)) }

  def mutable? = false

  # Carry the opener body forward on action-only versions (status change,
  # trash…) so a status flip never loses the customer's original message.
  def build_successor(event:, creator:, **changes)
    super.tap do |version|
      version.content = content.body unless changes.key?(:content)
    end
  end

  # Live replies under this ticket — current inbound+outbound versions, oldest
  # first. Mirrors Record#comments; delegated so callers can say ticket.replies.
  def replies
    Reply.where(id: record.children.active.replies.select(:recordable_id))
      .includes(:rich_text_content, creator: { avatar_attachment: :blob }, record: :parent)
      .order(:record_id)
  end
end
