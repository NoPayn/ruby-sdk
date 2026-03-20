# frozen_string_literal: true

require_relative "test_helper"
require "json"

class TestClient < Minitest::Test
  API_KEY     = "test-api-key"
  MERCHANT_ID = "test-merchant"
  BASE_URL    = "https://api.nopayn.co.uk"

  ORDER_RESPONSE = {
    "id"                => "uuid-order-1",
    "amount"            => 1295,
    "currency"          => "EUR",
    "status"            => "new",
    "description"       => "Test order",
    "merchant_order_id" => "DEMO-001",
    "return_url"        => "https://example.com/success",
    "failure_url"       => "https://example.com/failure",
    "order_url"         => "https://api.nopayn.co.uk/pay/uuid-order-1/",
    "created"           => "2026-01-01T12:00:00Z",
    "modified"          => "2026-01-01T12:00:00Z",
    "transactions"      => [
      {
        "id"                => "uuid-txn-1",
        "amount"            => 1295,
        "currency"          => "EUR",
        "payment_method"    => "credit-card",
        "payment_url"       => "https://api.nopayn.co.uk/redirect/uuid-txn-1/to/payment/",
        "status"            => "new",
        "created"           => "2026-01-01T12:00:00Z",
        "modified"          => "2026-01-01T12:00:00Z",
        "expiration_period" => "PT30M"
      }
    ]
  }.freeze

  REFUND_RESPONSE = {
    "id"     => "uuid-refund-1",
    "amount" => 500,
    "status" => "pending"
  }.freeze

  def setup
    @client = NoPayn::Client.new(api_key: API_KEY, merchant_id: MERCHANT_ID, base_url: BASE_URL)
  end

  def test_missing_api_key_raises
    assert_raises(NoPayn::Error) { NoPayn::Client.new(api_key: "", merchant_id: MERCHANT_ID) }
    assert_raises(NoPayn::Error) { NoPayn::Client.new(api_key: nil, merchant_id: MERCHANT_ID) }
  end

  def test_missing_merchant_id_raises
    assert_raises(NoPayn::Error) { NoPayn::Client.new(api_key: API_KEY, merchant_id: "") }
    assert_raises(NoPayn::Error) { NoPayn::Client.new(api_key: API_KEY, merchant_id: nil) }
  end

  def test_create_order
    stub_request(:post, "#{BASE_URL}/v1/orders/")
      .with(
        headers: { "Content-Type" => "application/json", "Accept" => "application/json" },
        body: hash_including("amount" => 1295, "currency" => "EUR")
      )
      .to_return(status: 201, body: JSON.generate(ORDER_RESPONSE), headers: { "Content-Type" => "application/json" })

    order = @client.create_order(amount: 1295, currency: "EUR", description: "Test order", merchant_order_id: "DEMO-001")

    assert_equal "uuid-order-1", order.id
    assert_equal 1295, order.amount
    assert_equal "EUR", order.currency
    assert_equal "new", order.status
    assert_equal "https://api.nopayn.co.uk/pay/uuid-order-1/", order.order_url
    assert_equal 1, order.transactions.size
    assert_equal "credit-card", order.transactions.first.payment_method
  end

  def test_get_order
    stub_request(:get, "#{BASE_URL}/v1/orders/uuid-order-1/")
      .to_return(status: 200, body: JSON.generate(ORDER_RESPONSE), headers: { "Content-Type" => "application/json" })

    order = @client.get_order("uuid-order-1")

    assert_equal "uuid-order-1", order.id
    assert_equal "new", order.status
  end

  def test_create_refund
    stub_request(:post, "#{BASE_URL}/v1/orders/uuid-order-1/refunds/")
      .with(body: hash_including("amount" => 500))
      .to_return(status: 201, body: JSON.generate(REFUND_RESPONSE), headers: { "Content-Type" => "application/json" })

    refund = @client.create_refund("uuid-order-1", 500, description: "Customer returned item")

    assert_equal "uuid-refund-1", refund.id
    assert_equal 500, refund.amount
    assert_equal "pending", refund.status
  end

  def test_create_refund_without_description
    stub_request(:post, "#{BASE_URL}/v1/orders/uuid-order-1/refunds/")
      .with(body: { "amount" => 500 }.to_json)
      .to_return(status: 201, body: JSON.generate(REFUND_RESPONSE), headers: { "Content-Type" => "application/json" })

    refund = @client.create_refund("uuid-order-1", 500)
    assert_equal "pending", refund.status
  end

  def test_generate_payment_url
    stub_request(:post, "#{BASE_URL}/v1/orders/")
      .to_return(status: 201, body: JSON.generate(ORDER_RESPONSE), headers: { "Content-Type" => "application/json" })

    result = @client.generate_payment_url(amount: 1295, currency: "EUR")

    assert_equal "uuid-order-1", result.order_id
    assert_equal "https://api.nopayn.co.uk/pay/uuid-order-1/", result.order_url
    assert_equal "https://api.nopayn.co.uk/redirect/uuid-txn-1/to/payment/", result.payment_url
    assert_match(/\A[0-9a-f]{64}\z/, result.signature)
    assert_equal "uuid-order-1", result.order.id
  end

  def test_generate_signature
    sig = @client.generate_signature(1295, "EUR", "order-1")
    expected = NoPayn::Signature.generate(API_KEY, 1295, "EUR", "order-1")
    assert_equal expected, sig
  end

  def test_verify_signature_roundtrip
    sig = @client.generate_signature(1295, "EUR", "order-1")
    assert @client.verify_signature(1295, "EUR", "order-1", sig)
  end

  def test_api_error_raises
    error_body = { "error" => { "value" => "Invalid amount" } }
    stub_request(:post, "#{BASE_URL}/v1/orders/")
      .to_return(status: 400, body: JSON.generate(error_body), headers: { "Content-Type" => "application/json" })

    err = assert_raises(NoPayn::ApiError) { @client.create_order(amount: -1, currency: "EUR") }
    assert_equal 400, err.status_code
    assert_includes err.message, "Invalid amount"
    assert_equal error_body, err.error_body
  end

  def test_api_error_detail_field
    error_body = { "detail" => "Not found" }
    stub_request(:get, "#{BASE_URL}/v1/orders/missing/")
      .to_return(status: 404, body: JSON.generate(error_body), headers: { "Content-Type" => "application/json" })

    err = assert_raises(NoPayn::ApiError) { @client.get_order("missing") }
    assert_equal 404, err.status_code
    assert_includes err.message, "Not found"
  end

  def test_network_error_raises
    stub_request(:get, "#{BASE_URL}/v1/orders/uuid-order-1/").to_raise(SocketError.new("getaddrinfo failed"))

    err = assert_raises(NoPayn::Error) { @client.get_order("uuid-order-1") }
    assert_includes err.message, "Network error"
  end

  def test_base_url_trailing_slash_stripped
    client = NoPayn::Client.new(api_key: API_KEY, merchant_id: MERCHANT_ID, base_url: "https://api.nopayn.co.uk/")

    stub_request(:get, "https://api.nopayn.co.uk/v1/orders/test/")
      .to_return(status: 200, body: JSON.generate(ORDER_RESPONSE), headers: { "Content-Type" => "application/json" })

    order = client.get_order("test")
    assert_equal "uuid-order-1", order.id
  end

  def test_order_body_includes_optional_params
    stub_request(:post, "#{BASE_URL}/v1/orders/")
      .with(body: hash_including(
        "locale" => "de-DE",
        "payment_methods" => ["credit-card"],
        "expiration_period" => "PT30M",
        "webhook_url" => "https://example.com/webhook"
      ))
      .to_return(status: 201, body: JSON.generate(ORDER_RESPONSE), headers: { "Content-Type" => "application/json" })

    @client.create_order(
      amount: 1295, currency: "EUR",
      locale: "de-DE", payment_methods: ["credit-card"],
      expiration_period: "PT30M", webhook_url: "https://example.com/webhook"
    )

    assert_requested :post, "#{BASE_URL}/v1/orders/"
  end
end
