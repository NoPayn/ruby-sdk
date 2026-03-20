# frozen_string_literal: true

module NoPayn
  class Error < StandardError; end

  class ApiError < Error
    attr_reader :status_code, :error_body

    def initialize(status_code, message, error_body = nil)
      @status_code = status_code
      @error_body  = error_body
      super("NoPayn API error (HTTP #{status_code}): #{message}")
    end
  end

  class WebhookError < Error; end
end
