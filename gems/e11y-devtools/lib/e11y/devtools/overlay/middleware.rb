# frozen_string_literal: true

module E11y
  module Devtools
    module Overlay
      # Rack middleware that injects the e11y overlay badge into HTML responses.
      #
      # Skips injection for:
      # - XHR requests (X-Requested-With: XMLHttpRequest)
      # - Asset paths (/assets/, /packs/, /_e11y/)
      # - Non-HTML responses
      class Middleware
        OVERLAY_SNIPPET = <<~HTML

          <!-- e11y-overlay -->
          <script id="e11y-overlay-loader">
            (function() {
              var s = document.createElement('script');
              s.src = '/_e11y/overlay.js';
              s.defer = true;
              document.head.appendChild(s);
            })();
          </script>
        HTML

        def initialize(app)
          @app = app
        end

        def call(env)
          status, headers, body = @app.call(env)
          return [status, headers, body] unless injectable?(env, headers)

          new_body = inject_overlay(body, env["e11y.trace_id"])
          [status, update_content_length(headers, new_body), [new_body]]
        end

        private

        def injectable?(env, headers)
          !xhr?(env) && !asset_path?(env) && html_response?(headers)
        end

        def xhr?(env)
          env["HTTP_X_REQUESTED_WITH"]&.downcase == "xmlhttprequest"
        end

        def asset_path?(env)
          path = env["PATH_INFO"] || ""
          path.start_with?("/assets/", "/packs/", "/_e11y/")
        end

        def html_response?(headers)
          ct = headers["Content-Type"] || headers["content-type"] || ""
          ct.include?("text/html")
        end

        def inject_overlay(body, trace_id)
          full = body.respond_to?(:join) ? body.join : body.to_s
          snippet = trace_id_script(trace_id) + OVERLAY_SNIPPET
          full.sub("</body>", "#{snippet}</body>")
        end

        def trace_id_script(trace_id)
          return "" unless trace_id

          "<script>window.__E11Y_TRACE_ID__ = '#{trace_id}';</script>\n"
        end

        def update_content_length(headers, new_body)
          h = headers.dup
          h.delete("Content-Length")
          h.delete("content-length")
          h["Content-Length"] = new_body.bytesize.to_s
          h
        end
      end
    end
  end
end
