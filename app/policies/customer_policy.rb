# The support desk is staff-facing: customers, licenses and tickets are the
# admin's (support agent's) workspace. Single-tenant install, so there's no
# per-customer scoping — either you administer the desk or you don't.
class CustomerPolicy < ApplicationPolicy
  def manage?
    return allow! if admin?

    deny! :not_admin
  end
end
