require "test_helper"

class RescueMalformedParamsTest < ActiveSupport::TestCase
  # Rack's multipart parser force-encodes a part's *name* to match a
  # "charset=..." parameter on that part's own Content-Type
  # (rack/multipart/parser.rb#tag_multipart_encoding). A part declaring
  # "charset=UTF-16LE" makes Rack::MethodOverride's read of req.POST raise
  # Encoding::CompatibilityError when it compares that name against a UTF-8
  # "[" literal (Rack::QueryParser#_normalize_params) -- see fault 134296687.
  def multipart_env(body, boundary: "----boundary")
    {
      "REQUEST_METHOD" => "POST",
      "CONTENT_TYPE" => "multipart/form-data; boundary=#{boundary}",
      "CONTENT_LENGTH" => body.bytesize.to_s,
      "rack.input" => StringIO.new(body),
      "rack.errors" => StringIO.new,
      "PATH_INFO" => "/",
      "SERVER_NAME" => "example.org",
      "SERVER_PORT" => "80",
      "QUERY_STRING" => "",
      "rack.version" => [ 1, 3 ],
      "rack.url_scheme" => "http"
    }
  end

  def malformed_body(boundary)
    [
      "--#{boundary}\r\n",
      "Content-Disposition: form-data; name=\"foo\"\r\n",
      "Content-Type: text/plain; charset=UTF-16LE\r\n",
      "\r\n",
      "bar\r\n",
      "--#{boundary}--\r\n"
    ].join
  end

  def well_formed_body(boundary)
    [
      "--#{boundary}\r\n",
      "Content-Disposition: form-data; name=\"foo\"\r\n",
      "\r\n",
      "bar\r\n",
      "--#{boundary}--\r\n"
    ].join
  end

  test "turns the malformed multipart request into a 400 instead of crashing" do
    boundary = "----boundary"
    app = ->(_env) { [ 200, {}, [ "ok" ] ] }
    stack = RescueMalformedParams.new(Rack::MethodOverride.new(app))

    status, _headers, body = stack.call(multipart_env(malformed_body(boundary), boundary: boundary))

    assert_equal 400, status
    assert_equal [ "Bad Request" ], body
  end

  test "negative check: the same payload crashes Rack::MethodOverride without this middleware" do
    boundary = "----boundary"
    app = ->(_env) { [ 200, {}, [ "ok" ] ] }

    assert_raises(Encoding::CompatibilityError) do
      Rack::MethodOverride.new(app).call(multipart_env(malformed_body(boundary), boundary: boundary))
    end
  end

  test "leaves well-formed multipart requests alone" do
    boundary = "----boundary"
    app = ->(_env) { [ 200, {}, [ "ok" ] ] }
    stack = RescueMalformedParams.new(Rack::MethodOverride.new(app))

    status, _headers, body = stack.call(multipart_env(well_formed_body(boundary), boundary: boundary))

    assert_equal 200, status
    assert_equal [ "ok" ], body
  end
end
