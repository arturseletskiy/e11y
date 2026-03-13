# frozen_string_literal: true

module E11y
  module Tracing
    # Monkey-patch for Net::HTTP that injects W3C traceparent into every request.
    #
    # Applied via +prepend+ so it wraps the original +#request+ method:
    #
    #   E11y::Tracing.patch_net_http!
    #   # From this point all Net::HTTP requests carry the traceparent header.
    #
    # The patch is idempotent — prepending twice is prevented by checking
    # +Net::HTTP.ancestors+.
    #
    # @see E11y::Tracing.patch_net_http!
    # @see E11y::Tracing::Propagator
    module NetHTTPPatch
      # Inject traceparent header then delegate to the original Net::HTTP#request.
      #
      # Skips injection if traceparent is already set on the request object
      # (e.g., caller set it manually).
      #
      # @param req  [Net::HTTPRequest] Outgoing HTTP request object
      # @param body [String, nil]      Optional body
      # @return [Net::HTTPResponse]
      def request(req, body = nil, &)
        header_value = Propagator.build_traceparent
        req[Propagator::TRACEPARENT_HEADER] = header_value if header_value && !req[Propagator::TRACEPARENT_HEADER]
        super
      end
    end
  end
end
