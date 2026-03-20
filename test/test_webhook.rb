# frozen_string_literal: true

require_relative "test_helper"
require "json"

class TestWebhook < Minitest::Test
  API_KEY     = "test-api-key"
  MERCHANT_ID = "test-merchant"
  BASE_URL    = "https://api.nopayn.co.uk"

  COMPLETED_ORDER_RESPONSE = {
    "id"           => "uuid-order-1",
    "amount"       => 1295,
    "currency"     => "EUR",
    "status"       => "completed",
    "created"      => "2026-01-01T12:00:00Z",
    "modified"     => "2026-01-01T12:01:00Z",
    "completed"    => "2026-01-01T12:01:00Z",
    "transactions" => []
  }.freeze

  NEW_ORDER_RESPONSE = {
    "id"           => "uuid-order-2",
    "amount"       => 500,
    "currency"     => "EUR",
    "status"       => "new",
    "created"      => "2026-01-01T12:00:00Z",
    "modified"     => "2026-01-01T12:00:00Z",
    "transactions" => []
  }.freeze

  def setup
    @client = NoPayn::Client.new(api_key: API_KEY, merchant_id: MERCHANT_ID, base_url: BASE_URL)
  end

  def test_parse_webhook_body_valid
    payload = JSON.generate({ event: "status_changed", order_id: "uuid-order-1", project_id: "proj-1" })
    result = @client.parse_webhook_body(payload)

    assert_equal "status_changed", result.event
    assert_equal "uuid-order-1", result.order_id
    assert_equal "proj-1", result.project_id
  end

  def test_parse_webhook_body_without_project_id
    payload = JSON.generate({ event: "status_changed", order_id: "uuid-order-1" })
    result = @client.parse_webhook_body(payload)

    assert_equal "uuid-order-1", result.order_id
    assert_nil result.project_id
  end

  def test_parse_webhook_body_invalid_json
    assert_raises(NoPayn::WebhookError) { @client.parse_webhook_body("not json") }
  end

  def test_parse_webhook_body_missing_order_id
    payload = JSON.generate({ event: "status_changed" })
    assert_raises(NoPayn::WebhookError) { @client.parse_webhook_body(payload) }
  end

  def test_parse_webhook_body_empty_order_id
    payload = JSON.generate({ event: "status_changed", order_id: "" })
    assert_raises(NoPayn::WebhookError) { @client.parse_webhook_body(payload) }
  end

  def test_verify_webhook_completed
    stub_request(:get, "#{BASE_URL}/v1/orders/uuid-order-1/")
      .to_return(status: 200, body: JSON.generate(COMPLETED_ORDER_RESPONSE), headers: { "Content-Type" => "application/json" })

    payload = JSON.generate({ event: "status_changed", order_id: "uuid-order-1" })
    result = @client.verify_webhook(payload)

    assert_equal "uuid-order-1", result.order_id
    assert_equal "completed", result.order.status
    assert result.is_final
  end

  def test_verify_webhook_non_final
    stub_request(:get, "#{BASE_URL}/v1/orders/uuid-order-2/")
      .to_return(status: 200, body: JSON.generate(NEW_ORDER_RESPONSE), headers: { "Content-Type" => "application/json" })

    payload = JSON.generate({ event: "status_changed", order_id: "uuid-order-2" })
    result = @client.verify_webhook(payload)

    assert_equal "uuid-order-2", result.order_id
    assert_equal "new", result.order.status
    refute result.is_final
  end

  def test_verify_webhook_all_final_statuses
    %w[completed cancelled expired error].each do |status|
      order_resp = COMPLETED_ORDER_RESPONSE.merge("id" => "order-#{status}", "status" => status)

      stub_request(:get, "#{BASE_URL}/v1/orders/order-#{status}/")
        .to_return(status: 200, body: JSON.generate(order_resp), headers: { "Content-Type" => "application/json" })

      payload = JSON.generate({ event: "status_changed", order_id: "order-#{status}" })
      result = @client.verify_webhook(payload)

      assert result.is_final, "Expected #{status} to be final"
    end
  end

  def test_verify_webhook_non_final_statuses
    %w[new processing].each do |status|
      order_resp = NEW_ORDER_RESPONSE.merge("id" => "order-#{status}", "status" => status)

      stub_request(:get, "#{BASE_URL}/v1/orders/order-#{status}/")
        .to_return(status: 200, body: JSON.generate(order_resp), headers: { "Content-Type" => "application/json" })

      payload = JSON.generate({ event: "status_changed", order_id: "order-#{status}" })
      result = @client.verify_webhook(payload)

      refute result.is_final, "Expected #{status} to not be final"
    end
  end

  def test_verify_webhook_invalid_json_raises
    assert_raises(NoPayn::WebhookError) { @client.verify_webhook("{broken") }
  end
end
