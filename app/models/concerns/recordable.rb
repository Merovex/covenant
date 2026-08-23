# Mix into a content model to make its rows the versions of a Record (ADR
# 0007). Every version carries: record_id (which record it belongs to),
# creator_id (who made this version), and event (what happened — a display tag,
# never queried for state). The record's recordable pointer is the cursor to
# the current version; superseded versions stay put as history.
module Recordable
  extend ActiveSupport::Concern

  # "synced" tags a version written by an external mirror (Lemon Squeezy), so
  # the history reads "synced" rather than implying a person edited it.
  EVENTS = %w[ created updated scheduled unscheduled published unpublished pinned unpinned trashed restored synced ]

  included do
    # Optional at the AR layer only so a first version can validate before its
    # record row exists (they're created in one transaction — see
    # PostsController#create); the DB's NOT NULL is the hard invariant.
    belongs_to :record, optional: true
    belongs_to :creator, class_name: "User", default: -> { Current.user }

    enum :event, EVENTS.index_by(&:itself), default: :created, prefix: true
  end

  # Versions are mutable only while drafted ("draft churn is nobody's
  # business"); every state the world ever saw is permanently recorded.
  def mutable? = drafted?

  # How long trashed content lingers before the purge job may destroy it.
  # Types with legal exposure override (see Post).
  def retention_period = 30.days

  # Copy of self for the next version: scalars carry forward, then `changes`
  # apply on top. Content-bearing types override #content= to mint a new Body
  # only when the text is part of the change. Without an acting user (e.g.
  # background jobs) the version keeps the previous actor.
  def build_successor(event:, creator:, **changes)
    dup.tap do |version|
      version.assign_attributes(event: event, **changes)
      version.creator = creator if creator
    end
  end

  # In-place edit of the current draft version (no new row, no event).
  def amend(**changes)
    update(changes)
    self
  end
end
