require "test_helper"

class ChatLinesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:alice)
  end

  test "chat page renders the transcript, boost strips, the context menu, and the composer" do
    get chatroom_path
    assert_response :success

    assert_select "turbo-frame#chat_line_#{records(:hello_line).id}" do
      assert_select ".chat__bubble", text: /Morning/
      assert_select "summary.boosts__prompt"
      assert_select ".menu__item", text: "Reply"
      assert_select "a.menu__item[href=?]", edit_chat_line_path(records(:hello_line)), text: "Edit"
      assert_select ".menu__item", text: "Move to trash"
    end
    assert_select "form[action=?] textarea[name=?]", chat_lines_path, "chat_line[content]"
  end

  test "create originates a parentless chat line record" do
    assert_difference -> { Record.active.chat_lines.count } do
      post chat_lines_path, params: { chat_line: { content: "Hello!" } }
    end

    record = Record.chat_lines.order(:id).last
    assert_nil record.parent_id
    assert_equal users(:alice), record.creator
    assert_redirected_to chatroom_path(anchor: "chat_line_#{record.id}")
  end

  test "create keeps typed newlines and neuters typed markup" do
    post chat_lines_path, params: { chat_line: { content: "One\r\nTwo <b>bold</b>" } }

    line = Record.chat_lines.order(:id).last.recordable
    assert_equal "One\nTwo <b>bold</b>", line.content.to_plain_text
  end

  test "create rejects a blank line" do
    assert_no_difference -> { ChatLine.count } do
      post chat_lines_path, params: { chat_line: { content: "" } }
    end
    assert_redirected_to chatroom_path
  end

  test "reply quotes the line into the composer" do
    get chatroom_path(reply_to: records(:hello_line).id)
    assert_response :success
    assert_select "form textarea", text: /> Morning, everyone!/
  end

  test "edit renders the inline editor in the line's frame" do
    get edit_chat_line_path(records(:hello_line))
    assert_response :success
    assert_select "turbo-frame#chat_line_#{records(:hello_line).id} textarea[name=?]", "chat_line[content]",
      text: "Morning, everyone!"
  end

  test "edit cannot touch someone else's line" do
    sign_in_as users(:bob)
    get edit_chat_line_path(records(:hello_line))
    assert_response :not_found
  end

  test "update lands as a tracked version and shows the Edited marker" do
    record = records(:hello_line)

    assert_difference -> { record.versions.count } do
      patch chat_line_path(record), params: { chat_line: { content: "Morning, all!" } }
    end

    assert_redirected_to chatroom_path(anchor: "chat_line_#{record.id}")
    assert_equal "Morning, all!", record.reload.recordable.content.to_plain_text

    follow_redirect!
    assert_select "turbo-frame#chat_line_#{record.id}", text: /Edited/
  end

  test "update with blank content re-renders the editor" do
    patch chat_line_path(records(:hello_line)), params: { chat_line: { content: "" } }
    assert_response :unprocessable_entity
    assert_select "textarea[name=?]", "chat_line[content]"
  end

  test "destroy trashes your own line" do
    delete chat_line_path(records(:hello_line))

    assert records(:hello_line).reload.trashed?
    assert_redirected_to chatroom_path

    follow_redirect!
    assert_select "#chat_line_#{records(:hello_line).id}", count: 0
  end

  test "destroy cannot touch someone else's line" do
    sign_in_as users(:bob)

    delete chat_line_path(records(:hello_line))

    assert_response :not_found
    assert_not records(:hello_line).reload.trashed?
  end

  test "boosting a chat line lands back on the chat page" do
    assert_difference -> { records(:hello_line).boosts.count } do
      post record_boosts_path(records(:hello_line)), params: { boost: { content: "👀" } }
    end

    assert_redirected_to chatroom_path(anchor: "boosts_record_#{records(:hello_line).id}")
  end
end
