class ApplicationController < ActionController::Base
  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
  # NOTE: allow_browser :modern lives in AuthenticatedController — not here.
  # ApprovalsController and WebhooksController must accept any client (email
  # clients, API callers) and must NOT enforce a modern browser constraint.
end
