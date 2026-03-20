# frozen_string_literal: true

require "sinatra"
require "json"
require "nopayn"

set :port, (ENV["PORT"] || 3000).to_i
set :bind, "0.0.0.0"
set :views, File.join(__dir__, "views")

NOPAYN_API_KEY     = ENV.fetch("NOPAYN_API_KEY", "")
NOPAYN_MERCHANT_ID = ENV.fetch("NOPAYN_MERCHANT_ID", "")
NOPAYN_BASE_URL    = ENV.fetch("NOPAYN_BASE_URL", "https://api.nopayn.co.uk")
PUBLIC_URL         = ENV.fetch("PUBLIC_URL", "http://localhost:3000")

if NOPAYN_API_KEY.empty? || NOPAYN_MERCHANT_ID.empty?
  abort "Set NOPAYN_API_KEY and NOPAYN_MERCHANT_ID environment variables"
end

NOPAYN = NoPayn::Client.new(
  api_key:     NOPAYN_API_KEY,
  merchant_id: NOPAYN_MERCHANT_ID,
  base_url:    NOPAYN_BASE_URL
)

get "/" do
  erb :index, locals: { public_url: PUBLIC_URL }
end

post "/pay" do
  amount   = (Float(params[:amount] || "9.95") * 100).round
  currency = params[:currency] || "EUR"
  order_id = "DEMO-#{(Time.now.to_f * 1000).to_i}"

  result = NOPAYN.generate_payment_url(
    amount:            amount,
    currency:          currency,
    merchant_order_id: order_id,
    description:       "Demo order #{order_id}",
    return_url:        "#{PUBLIC_URL}/success?order_id=#{order_id}",
    failure_url:       "#{PUBLIC_URL}/failure?order_id=#{order_id}",
    webhook_url:       "#{PUBLIC_URL}/webhook",
    locale:            params[:locale] || "en-GB",
    expiration_period: "PT30M"
  )

  puts "[PAY] Order #{result.order_id} created — signature: #{result.signature}"

  redirect_to = result.payment_url || result.order_url
  redirect redirect_to
rescue StandardError => e
  puts "[PAY] Error: #{e.message}"
  status 500
  erb :failure, locals: { title: "Payment Error", message: e.message }
end

get "/success" do
  erb :success, locals: { order_id: params[:order_id] || "(unknown)" }
end

get "/failure" do
  erb :failure, locals: {
    title:   "Payment Failed",
    message: "Order #{params[:order_id] || '(unknown)'} was not completed."
  }
end

post "/webhook" do
  request.body.rewind
  raw_body = request.body.read

  begin
    verified = NOPAYN.verify_webhook(raw_body)
    puts "[WEBHOOK] Order #{verified.order_id} → #{verified.order.status} (final: #{verified.is_final})"
  rescue StandardError => e
    puts "[WEBHOOK] Verification failed: #{e.message}"
  end

  status 200
  ""
end

get "/status/:order_id" do
  content_type :json

  order = NOPAYN.get_order(params[:order_id])
  JSON.generate(
    id: order.id, amount: order.amount, currency: order.currency,
    status: order.status, created: order.created
  )
rescue StandardError => e
  status 500
  JSON.generate(error: e.message)
end
