# Tickets (and the replies threaded under them) are the support agent's queue
# — admin only, like the rest of the desk. Gated at the class level, so a
# ticket's spine Record never has to resolve to RecordPolicy.
class TicketPolicy < ApplicationPolicy
  def manage?
    return allow! if admin?

    deny! :not_admin
  end
end
