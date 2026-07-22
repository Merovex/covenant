# Saves the staff-only note on any Notable (a Record behind a Ticket/License, or
# a Customer). The target is carried as a signed, purpose-scoped GlobalID so one
# route serves every notable and nobody can point it at something else. Admin
# only, enforced through the notable's own policy (RecordPolicy/CustomerPolicy).
class NotesController < ApplicationController
  def update
    notable = GlobalID::Locator.locate_signed(params[:sgid], for: "note")
    return render_not_found unless notable.is_a?(Notable)

    authorize! notable, to: :manage
    notable.update!(note: params.require(:notable).permit(:note)[:note])
    redirect_back fallback_location: root_path, notice: "Note saved."
  end
end
