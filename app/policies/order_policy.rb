# Orders are the desk's mirror of Lemon Squeezy sales — admin only, like
# customers and licenses. See CustomerPolicy for the rationale.
class OrderPolicy < ApplicationPolicy
  def manage?
    return allow! if admin?

    deny! :not_admin
  end
end
