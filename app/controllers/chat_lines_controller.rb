# Says a line in the room (create), fixes one (update — chat lines are never
# mutable, so every edit lands as a tracked version), or takes one back
# (destroy — the same trash ceremony as everything on the spine).
# A chat line's record has no parent: the install has a single room.
class ChatLinesController < ApplicationController
  before_action :set_record, only: %i[edit update destroy]

  def create
    @chat_line = ChatLine.new(content: formatted_content)

    if @chat_line.valid?
      Record.originate(@chat_line)
      redirect_to chatroom_path(anchor: "chat_line_#{@chat_line.record_id}")
    else
      redirect_to chatroom_path, alert: "Say something first."
    end
  end

  def edit
  end

  def update
    @chat_line = @record.revise(event: :updated, content: formatted_content)

    if @chat_line.errors.none?
      redirect_to chatroom_path(anchor: "chat_line_#{@record.id}")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @record.trash
    redirect_to chatroom_path, notice: "Chat line moved to trash."
  end

  private
    # Member actions are yours-only: creator scoping is the authorization,
    # so someone else's line 404s rather than 403s.
    def set_record
      @record = Record.active.chat_lines.where(creator: Current.user).find(params[:id])
      @chat_line = @record.recordable
    end

    def chat_line_params
      params.expect(chat_line: [ :content ])
    end

    # Chat is typed plain: escape it, then honor the newlines Ctrl+Enter put
    # in (Action Text stores HTML, where a bare newline is just a space).
    def formatted_content
      ERB::Util.html_escape(chat_line_params[:content].to_s.strip).gsub(/\r?\n/, "<br>")
    end
end
