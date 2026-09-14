# Scanners occasionally POST a multipart body where a field's own part
# declares "Content-Type: text/plain; charset=UTF-16LE". Rack's multipart
# parser force-encodes that field's *name* (not just its body) to match
# (rack/multipart/parser.rb#tag_multipart_encoding), so by the time
# Rack::MethodOverride reads req.POST looking for `_method`, the param name
# is UTF-16LE while Rack::QueryParser compares it against the UTF-8 literal
# "[" -- raising Encoding::CompatibilityError instead of returning false.
#
# Rack::MethodOverride already rescues its own family of bad-input errors
# (Utils::InvalidParameterError, QueryParser::ParamsTooDeepError, ...) and
# maps them to a no-op, but not this one. Worse, MethodOverride sits above
# ActionDispatch::ShowExceptions in the middleware stack, so nothing in
# Rails ever gets a chance to turn the exception into a 400 -- it surfaces
# as a raw, unhandled 500.
#
# Insert this ahead of Rack::MethodOverride so the same class of malformed
# request is turned into a 400 instead.
class RescueMalformedParams
  def initialize(app)
    @app = app
  end

  def call(env)
    @app.call(env)
  rescue Encoding::CompatibilityError
    [ 400, { "Content-Type" => "text/plain" }, [ "Bad Request" ] ]
  end
end
