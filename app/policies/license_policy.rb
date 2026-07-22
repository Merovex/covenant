# Licenses are staff-managed support-desk records — admin only, like the rest
# of the desk. See CustomerPolicy for the rationale.
class LicensePolicy < ApplicationPolicy
  def manage?
    return allow! if admin?

    deny! :not_admin
  end
end
