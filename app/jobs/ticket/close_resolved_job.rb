# Archives tickets that have sat `resolved` for a full week — "resolved and
# quiet" → `closed`. Runs daily on the recurring schedule (config/recurring.yml).
# resolved_at is stamped by Ticket#build_successor and cleared the moment a
# ticket leaves resolved (e.g. the customer replies), so a reopened ticket
# never gets swept up. Closing is a normal spine revision, authored by the
# system user since there's no acting agent in a background job.
class Ticket::CloseResolvedJob < ApplicationJob
  def perform
    Ticket.current.resolved.where(resolved_at: ..1.week.ago).find_each do |ticket|
      ticket.record.revise(event: :updated, status: :closed, creator: User.system)
    end
  end
end
