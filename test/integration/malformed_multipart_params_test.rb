require "test_helper"

# Reproduces Honeybadger fault 134296687: a scanner POSTs a multipart body
# whose own part declares "Content-Type: text/plain; charset=UTF-16LE".
# Rack force-encodes that part's *name* to UTF-16LE, and Rack::MethodOverride
# reading req.POST to look for `_method` blows up comparing that name against
# a UTF-8 "[" literal (Rack::QueryParser#_normalize_params) -- raising
# Encoding::CompatibilityError above ActionDispatch::ShowExceptions, so it
# used to reach production as a raw 500.
class MalformedMultipartParamsTest < ActionDispatch::IntegrationTest
  BOUNDARY = "----WebKitFormBoundaryx8jO2oVc6SWP3Sad"

  MALFORMED_BODY = [
    "--#{BOUNDARY}\r\n",
    "Content-Disposition: form-data; name=\"foo\"\r\n",
    "Content-Type: text/plain; charset=UTF-16LE\r\n",
    "\r\n",
    "bar\r\n",
    "--#{BOUNDARY}--\r\n"
  ].join

  def call_full_stack(path, body)
    env = Rack::MockRequest.env_for(
      path,
      method: "POST",
      "CONTENT_TYPE" => "multipart/form-data; boundary=#{BOUNDARY}",
      "CONTENT_LENGTH" => body.bytesize.to_s,
      "rack.input" => StringIO.new(body),
    )
    Rails.application.call(env)
  end

  test "the actual production payload gets a 400 from the real middleware stack, not a 500" do
    status, = call_full_stack("/session/new", MALFORMED_BODY)

    assert_equal 400, status
  end

  test "the actual production payload also 400s when posted to the root path" do
    status, = call_full_stack("/", MALFORMED_BODY)

    assert_equal 400, status
  end

  test "an ordinary request through the same path still serves normally" do
    get new_session_path
    assert_response :success
  end
end
