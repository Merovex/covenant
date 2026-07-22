# The stable identity every piece of content lives behind (ADR 0006/0007).
# Holds what never changes (creator, threading, position) plus two cursors:
# recordable (the current version) and trashed_at (the cheap list filter —
# trash history itself lives in the version rows). Deliberately tenant-
# agnostic: host apps that need scoping add their own column on this spine.
class Record < ApplicationRecord
  include Boostable

  # Content types that may live in the envelope; grows as recordables are added.
  RECORDABLE_TYPES = %w[ Post Comment ChatLine Message License Ticket Reply ]

  delegated_type :recordable, types: RECORDABLE_TYPES, optional: true
  belongs_to :creator, class_name: "User", default: -> { Current.user }

  # Reply-by-email routing token, minted per ticket Record and carried in the
  # outbound Message-ID. Tamper-proof (signed with secret_key_base) and
  # purpose-scoped. No expiry: customers reply weeks later. See TicketMailer /
  # TicketsMailbox for the round-trip.
  generates_token_for :ticket_reply

  # Self-referential threading: a comment's record will parent to the record it
  # comments on; same mechanism for any future child content.
  belongs_to :parent, class_name: "Record", optional: true
  has_many :children, class_name: "Record", foreign_key: :parent_id,
    inverse_of: :parent, dependent: :destroy

  scope :active,  -> { where(trashed_at: nil) }
  scope :trashed, -> { where.not(trashed_at: nil) }
  scope :purgeable, -> { trashed.where(purge_after: ..Time.current) }
  scope :posts, -> { where(recordable_type: "Post") }
  scope :comments, -> { where(recordable_type: "Comment") }
  scope :chat_lines, -> { where(recordable_type: "ChatLine") }
  scope :messages, -> { where(recordable_type: "Message") }
  scope :licenses, -> { where(recordable_type: "License") }
  scope :tickets, -> { where(recordable_type: "Ticket") }
  scope :replies, -> { where(recordable_type: "Reply") }
  scope :recently_active, -> { active.includes(:recordable).order(updated_at: :desc) }

  before_destroy :destroy_versions

  # Birth of a record: the row must exist before its first version can carry
  # record_id, then the cursor points at that version — one transaction. The
  # record's creator is the first version's author, always. Child content
  # (comments) passes the record it hangs from as parent.
  def self.originate(version, parent: nil)
    transaction do
      create!(recordable_type: version.class.name, creator: version.creator, parent: parent).tap do |record|
        version.update!(record: record)
        record.update!(recordable: version)
      end
    end
  end

  # All versions, oldest first. One type per record for life, so the class
  # comes straight from the delegated type.
  def versions
    recordable_class.where(record_id: id).order(:id)
  end

  # Insert the next immutable version and repoint the cursor. Returns the
  # version (unsaved, with errors, when invalid — the cursor then stays put).
  def revise(event:, creator: Current.user, **changes)
    version = recordable.build_successor(event: event, creator: creator, **changes)
    transaction do
      update!(recordable: version) if version.save
    end
    version
  end

  # The whole save policy in one ladder (ADR 0007): a requested transition
  # wins (publish beats schedule beats unschedule), folding the edit into the
  # transition version; otherwise the regime rule — drafts mutate in place,
  # published content versions on every save.
  def save_edit(creator: Current.user, publish: false, schedule_at: nil, unschedule: false, **changes)
    if publish && !recordable.published?
      recordable.publish(creator: creator, **changes)
    elsif schedule_at
      recordable.schedule(at: schedule_at, creator: creator, **changes)
    elsif unschedule && recordable.scheduled?
      recordable.unschedule(creator: creator, **changes)
    elsif recordable.mutable?
      recordable.amend(**changes)
    else
      revise(event: :updated, creator: creator, **changes)
    end
  end

  # Live comments under this record — current versions only, oldest first
  # (record ids are creation-ordered; version ids aren't, once edits land).
  def comments
    Comment.where(id: children.active.comments.select(:recordable_id))
      .includes(:rich_text_content, creator: { avatar_attachment: :blob },
        record: [ :parent, { boosts: { creator: { avatar_attachment: :blob } } } ])
      .order(:record_id)
  end

  def trashed? = trashed_at.present?

  # Staged deletion, always on the history regardless of draft/published.
  # Recoverable until the purge deadline: the recordable's retention_period
  # (30 days; 2 years for ever-published content — legal hold).
  def trash
    transaction do
      revise(event: :trashed)
      update! trashed_at: Time.current, purge_after: recordable.retention_period.from_now
    end
  end

  def restore
    transaction do
      revise(event: :restored)
      update! trashed_at: nil, purge_after: nil
    end
  end

  private
    def destroy_versions
      versions.find_each(&:destroy)
    end
end
