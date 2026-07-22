# Resolves the Record (the public identity — /tickets/:id is a Record id,
# never a version id) and its current version for ticket-facing controllers,
# including the nested reply composer (which keys off :ticket_id).
module TicketScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_record
  end

  private
    def set_record
      @record = Record.active.tickets.find(params[:ticket_id] || params[:id])
      @ticket = @record.recordable
    end
end
