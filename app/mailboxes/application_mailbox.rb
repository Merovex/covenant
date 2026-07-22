class ApplicationMailbox < ActionMailbox::Base
  # A dedicated support inbox: every message that reaches it is either a reply
  # to an existing ticket or the opener of a new one, so route it all to
  # TicketsMailbox, which decides which by inspecting the headers.
  routing all: :tickets
end
