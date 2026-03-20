# nopayn

Official Ruby SDK for the [NoPayn Payment Gateway](https://costplus.io). Simplifies the HPP (Hosted Payment Page) redirect flow, HMAC payload signing, and webhook verification.

[![CI](https://github.com/NoPayn/ruby-sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/NoPayn/ruby-sdk/actions/workflows/ci.yml)

## Features

- HMAC-SHA256 signature generation and constant-time verification
- Automatic snake_case mapping from the API to Ruby-friendly OpenStruct objects
- Webhook parsing + API-based order verification (as recommended by NoPayn)
- Tested across Ruby 3.1, 3.2, and 3.3
- Sinatra-based demo merchant app included

## Requirements

- Ruby >= 3.1
- A NoPayn / Cost+ merchant account — [manage.nopayn.io](https://manage.nopayn.io/)

## Installation

Add to your Gemfile:

```ruby
gem "nopayn"
```

Then run:

```bash
bundle install
```

Or install directly:

```bash
gem install nopayn
```

## Quick Start

### 1. Initialise the client

```ruby
require "nopayn"

nopayn = NoPayn::Client.new(
  api_key:     "your-api-key",      # From the NoPayn merchant portal
  merchant_id: "your-project"       # Your project/merchant ID
)
```

### 2. Create a payment and redirect to the HPP

```ruby
result = nopayn.generate_payment_url(
  amount:            1295,           # €12.95 in cents
  currency:          "EUR",
  merchant_order_id: "ORDER-001",
  description:       "Premium Widget",
  return_url:        "https://shop.example.com/success",
  failure_url:       "https://shop.example.com/failure",
  webhook_url:       "https://shop.example.com/webhook",
  locale:            "en-GB",
  expiration_period: "PT30M"
)

# Redirect the customer
# result.order_url   → HPP (customer picks payment method)
# result.payment_url → direct link to the first transaction's payment method
# result.signature   → HMAC-SHA256 for verification
# result.order_id    → NoPayn order UUID
```

### 3. Handle the webhook

```ruby
post "/webhook" do
  request.body.rewind
  raw_body = request.body.read

  verified = nopayn.verify_webhook(raw_body)

  puts verified.order.status  # "completed", "cancelled", etc.
  puts verified.is_final      # true when the order won't change

  if verified.order.status == "completed"
    # Fulfil the order
  end

  status 200
end
```

## API Reference

### `NoPayn::Client.new(api_key:, merchant_id:, base_url:)`

| Parameter | Type | Required | Default |
|-----------|------|----------|---------|
| `api_key` | `String` | Yes | — |
| `merchant_id` | `String` | Yes | — |
| `base_url` | `String` | No | `https://api.nopayn.co.uk` |

### `client.create_order(params) → OpenStruct`

Creates an order via `POST /v1/orders/`.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `:amount` | `Integer` | Yes | Amount in smallest currency unit (cents) |
| `:currency` | `String` | Yes | ISO 4217 code (`EUR`, `GBP`, `USD`, `NOK`, `SEK`) |
| `:merchant_order_id` | `String` | No | Your internal order reference |
| `:description` | `String` | No | Order description |
| `:return_url` | `String` | No | Redirect after successful payment |
| `:failure_url` | `String` | No | Redirect on cancel/expiry/error |
| `:webhook_url` | `String` | No | Async status-change notifications |
| `:locale` | `String` | No | HPP language (`en-GB`, `de-DE`, `nl-NL`, etc.) |
| `:payment_methods` | `Array<String>` | No | Filter HPP methods |
| `:expiration_period` | `String` | No | ISO 8601 duration (`PT30M`) |

**Available payment methods:** `credit-card`, `apple-pay`, `google-pay`, `vipps-mobilepay`

### `client.get_order(order_id) → OpenStruct`

Fetches order details via `GET /v1/orders/{id}/`.

### `client.create_refund(order_id, amount, description: nil) → OpenStruct`

Issues a full or partial refund via `POST /v1/orders/{id}/refunds/`.

### `client.generate_payment_url(params) → OpenStruct`

Convenience method that creates an order and returns:

```ruby
result.order_id     # NoPayn order UUID
result.order_url    # HPP URL
result.payment_url  # Direct payment URL (first transaction)
result.signature    # HMAC-SHA256 of amount:currency:order_id
result.order        # Full order OpenStruct
```

### `client.generate_signature(amount, currency, order_id) → String`

Generates an HMAC-SHA256 hex signature. The canonical message is `"#{amount}:#{currency}:#{order_id}"`, signed with the API key.

### `client.verify_signature(amount, currency, order_id, signature) → Boolean`

Constant-time verification of an HMAC-SHA256 signature. Returns `true` if valid.

### `client.verify_webhook(raw_body) → OpenStruct`

Parses the webhook body, then calls `GET /v1/orders/{id}/` to verify the actual status. Returns:

```ruby
result.order_id  # NoPayn order UUID from the webhook
result.order     # Order details fetched and verified via the API
result.is_final  # true for completed/cancelled/expired/error
```

### `client.parse_webhook_body(raw_body) → OpenStruct`

Parses and validates a webhook body without calling the API.

### Standalone HMAC Utilities

```ruby
require "nopayn"

sig = NoPayn::Signature.generate("your-api-key", 1295, "EUR", "order-uuid")
ok  = NoPayn::Signature.verify("your-api-key", 1295, "EUR", "order-uuid", sig)
```

## Error Handling

```ruby
require "nopayn"

begin
  nopayn.create_order(amount: 100, currency: "EUR")
rescue NoPayn::ApiError => e
  puts e.status_code  # 401, 400, etc.
  puts e.error_body   # Raw API error response
rescue NoPayn::Error => e
  puts e.message      # Network or parsing error
end
```

| Exception | Parent | Description |
|-----------|--------|-------------|
| `NoPayn::Error` | `StandardError` | Base error for all SDK errors |
| `NoPayn::ApiError` | `NoPayn::Error` | HTTP error from the API (has `status_code`, `error_body`) |
| `NoPayn::WebhookError` | `NoPayn::Error` | Invalid webhook payload |

## Order Statuses

| Status | Final? | Description |
|--------|--------|-------------|
| `new` | No | Order created |
| `processing` | No | Payment in progress |
| `completed` | Yes | Payment successful — deliver the goods |
| `cancelled` | Yes | Payment cancelled by customer |
| `expired` | Yes | Payment link timed out |
| `error` | Yes | Technical failure |

## Webhook Best Practices

1. **Always verify via the API** — the webhook payload only contains the order ID, never the status. The SDK's `verify_webhook` does this automatically.
2. **Return HTTP 200** to acknowledge receipt. Any other code triggers up to 10 retries (2 minutes apart).
3. **Implement a backup poller** — for orders older than 10 minutes that haven't reached a final status, poll `get_order` as a safety net.
4. **Be idempotent** — you may receive the same webhook multiple times.

## Demo Merchant Site

A Docker-based demo app is included for testing the full payment flow.

### Run with Docker Compose

```bash
cd demo

# Create a .env file
cat > .env << EOF
NOPAYN_API_KEY=your-api-key
NOPAYN_MERCHANT_ID=your-merchant-id
PUBLIC_URL=http://localhost:3000
EOF

docker compose up --build
```

Open [http://localhost:3000](http://localhost:3000) to see the demo checkout page.

### Run without Docker

```bash
# Install SDK dependencies
bundle install

# Install demo dependencies
cd demo && bundle install

# Start the server
NOPAYN_API_KEY=your-key NOPAYN_MERCHANT_ID=your-id ruby app.rb
```

## Testing

```bash
bundle install
bundle exec rake test
```

## Test Cards

Use these cards in NoPayn test mode (project status `active-testing`):

| Card | Number | Notes |
|------|--------|-------|
| Visa (frictionless) | `4018 8100 0010 0036` | No 3DS challenge |
| Mastercard (frictionless) | `5420 7110 0021 0016` | No 3DS challenge |
| Visa (3DS) | `4018 8100 0015 0015` | OTP: `0101` (success), `3333` (fail) |
| Mastercard (3DS) | `5299 9100 1000 0015` | OTP: `4445` (success), `9999` (fail) |

Use any future expiry date and any 3-digit CVC.

## License

MIT — see [LICENSE](LICENSE).

## Support

- NoPayn API docs: [dev.nopayn.io](https://dev.nopayn.io/)
- Merchant portal: [manage.nopayn.io](https://manage.nopayn.io/)
- Developer: [Cost+](https://costplus.io)
