# The single chatroom. Show is the transcript plus the composer; there is
# nothing else to it — lines have their own controller.
class ChatroomsController < ApplicationController
  def show
    @chat_lines = ChatLine.transcript

    # Replying quotes the line into the composer, Campfire style.
    if replying_to = Record.active.chat_lines.find_by(id: params[:reply_to])
      @composer_text = replying_to.recordable.content.to_plain_text.lines.map { |line| "> #{line}" }.join + "\n"
    end
  end
end
