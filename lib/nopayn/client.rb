# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "ostruct"

module NoPayn
  class Client
    DEFAULT_BASE_URL = "https://api.nopayn.co.uk"
    FINAL_STATUSES   = %w[completed cancelled expired error].freeze

    # @param api_key [String] NoPayn API key (used for HTTP Basic auth and HMAC signing)
    # @param merchant_id [String] Your merchant/project ID from the NoPayn dashboard
    # @param base_url [String] API base URL
    def initialize(api_key:, merchant_id:, base_url: DEFAULT_BASE_URL)
      raise NoPayn::Error, "api_key is required"     if api_key.nil? || api_key.empty?
      raise NoPayn::Error, "merchant_id is required"  if merchant_id.nil? || merchant_id.empty?

      @api_key     = api_key
      @merchant_id = merchant_id
      @base_url    = base_url.chomp("/")
    end

    # Create an order via POST /v1/orders/.
    # @param params [Hash] order parameters
    # @return [OpenStruct] order object with camelCase-style accessors
    def create_order(params)
      body = build_order_body(params)
      data = request(:post, "/v1/orders/", body)
      map_order(data)
    end

    # Fetch an existing order via GET /v1/orders/{id}/.
    # @param order_id [String]
    # @return [OpenStruct]
    def get_order(order_id)
      data = request(:get, "/v1/orders/#{uri_encode(order_id)}/")
      map_order(data)
    end

    # Issue a full or partial refund via POST /v1/orders/{id}/refunds/.
    # @param order_id [String]
    # @param amount [Integer] refund amount in cents
    # @param description [String, nil]
    # @return [OpenStruct]
    def create_refund(order_id, amount, description: nil)
      body = { amount: amount }
      body[:description] = description if description

      data = request(:post, "/v1/orders/#{uri_encode(order_id)}/refunds/", body)

      OpenStruct.new(
        id:     data["id"],
        amount: data["amount"],
        status: data["status"]
      )
    end

    # Create an order and return the HPP redirect URL with an HMAC signature.
    # @param params [Hash] same as create_order
    # @return [OpenStruct] with order_id, order_url, payment_url, signature, order
    def generate_payment_url(params)
      order = create_order(params)

      signature = NoPayn::Signature.generate(
        @api_key,
        params[:amount],
        params[:currency],
        order.id
      )

      OpenStruct.new(
        order_id:    order.id,
        order_url:   order.order_url,
        payment_url: order.transactions&.first&.payment_url,
        signature:   signature,
        order:       order
      )
    end

    # Generate an HMAC-SHA256 hex signature.
    # Canonical message: "#{amount}:#{currency}:#{order_id}"
    def generate_signature(amount, currency, order_id)
      NoPayn::Signature.generate(@api_key, amount, currency, order_id)
    end

    # Constant-time verification of an HMAC-SHA256 signature.
    # @return [Boolean]
    def verify_signature(amount, currency, order_id, signature)
      NoPayn::Signature.verify(@api_key, amount, currency, order_id, signature)
    end

    # Parse a raw webhook body into a structured payload.
    # @param raw_body [String]
    # @return [OpenStruct] with event, order_id, project_id
    # @raise [NoPayn::WebhookError] if the body is invalid
    def parse_webhook_body(raw_body)
      body = JSON.parse(raw_body)
    rescue JSON::ParserError
      raise NoPayn::WebhookError, "Invalid JSON in webhook body"
    else
      order_id = body["order_id"]
      raise NoPayn::WebhookError, "Missing order_id in webhook payload" if order_id.nil? || order_id.empty?

      OpenStruct.new(
        event:      body["event"],
        order_id:   order_id,
        project_id: body["project_id"]
      )
    end

    # Full webhook verification: parse the body, then call the API to confirm
    # the actual order status.
    # @param raw_body [String]
    # @return [OpenStruct] with order_id, order, is_final
    def verify_webhook(raw_body)
      payload = parse_webhook_body(raw_body)
      order   = get_order(payload.order_id)

      OpenStruct.new(
        order_id: payload.order_id,
        order:    order,
        is_final: FINAL_STATUSES.include?(order.status)
      )
    end

    private

    def request(method, endpoint, body = nil)
      uri = URI("#{@base_url}#{endpoint}")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")

      req = case method
            when :get  then Net::HTTP::Get.new(uri)
            when :post then Net::HTTP::Post.new(uri)
            else raise NoPayn::Error, "Unsupported HTTP method: #{method}"
            end

      req.basic_auth(@api_key, "")
      req["Accept"] = "application/json"

      if body && method != :get
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body)
      end

      begin
        response = http.request(req)
      rescue SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET,
             Net::OpenTimeout, Net::ReadTimeout => e
        raise NoPayn::Error, "Network error: #{e.message}"
      end

      text = response.body || ""

      begin
        data = text.empty? ? {} : JSON.parse(text)
      rescue JSON::ParserError
        raise NoPayn::Error, "Invalid JSON response: #{text[0, 200]}"
      end

      unless response.is_a?(Net::HTTPSuccess)
        error_msg = if data.is_a?(Hash)
                      nested = data["error"]
                      if nested.is_a?(Hash)
                        nested["value"] || nested["message"]
                      end || data["detail"] || "Unknown error"
                    else
                      "Unknown error"
                    end
        raise NoPayn::ApiError.new(response.code.to_i, error_msg, data)
      end

      data
    end

    def build_order_body(params)
      body = {
        amount:   params[:amount],
        currency: params[:currency]
      }

      body[:merchant_order_id] = params[:merchant_order_id] if params[:merchant_order_id]
      body[:description]       = params[:description]       if params[:description]
      body[:return_url]        = params[:return_url]        if params[:return_url]
      body[:failure_url]       = params[:failure_url]       if params[:failure_url]
      body[:webhook_url]       = params[:webhook_url]       if params[:webhook_url]
      body[:locale]            = params[:locale]            if params[:locale]
      body[:payment_methods]   = params[:payment_methods]   if params[:payment_methods]
      body[:expiration_period] = params[:expiration_period] if params[:expiration_period]

      body
    end

    def map_order(data)
      txns = (data["transactions"] || []).map { |t| map_transaction(t) }

      OpenStruct.new(
        id:                data["id"],
        amount:            data["amount"],
        currency:          data["currency"],
        status:            data["status"],
        description:       data["description"],
        merchant_order_id: data["merchant_order_id"],
        return_url:        data["return_url"],
        failure_url:       data["failure_url"],
        order_url:         data["order_url"],
        created:           data["created"],
        modified:          data["modified"],
        completed:         data["completed"],
        transactions:      txns
      )
    end

    def map_transaction(t)
      OpenStruct.new(
        id:                t["id"],
        amount:            t["amount"],
        currency:          t["currency"],
        payment_method:    t["payment_method"],
        payment_url:       t["payment_url"],
        status:            t["status"],
        created:           t["created"],
        modified:          t["modified"],
        expiration_period: t["expiration_period"]
      )
    end

    def uri_encode(str)
      URI.encode_uri_component(str)
    end
  end
end
