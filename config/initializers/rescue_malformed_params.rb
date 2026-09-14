# Multipart bodies with a part declared "charset=UTF-16LE" make Rack force
# that part's *name* to UTF-16LE (rack/multipart/parser.rb#tag_multipart_encoding).
# Rack::MethodOverride then compares that name against a UTF-8 "[" literal and
# raises Encoding::CompatibilityError -- and it sits above
# ActionDispatch::ShowExceptions, so the error would otherwise reach
# production as a raw 500. See app/middleware/rescue_malformed_params.rb.
#
# Loaded with a plain `require` rather than relying on autoloading: Zeitwerk's
# main autoloader isn't set up until the :setup_main_autoloader finisher,
# which runs after every config/initializers/*.rb file, so referencing the
# bare constant here raises "uninitialized constant RescueMalformedParams".
require Rails.root.join("app/middleware/rescue_malformed_params")

Rails.application.config.middleware.insert_before Rack::MethodOverride, RescueMalformedParams
