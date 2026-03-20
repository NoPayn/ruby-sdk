# frozen_string_literal: true

require_relative "test_helper"

class TestSignature < Minitest::Test
  SECRET   = "test-secret-key"
  AMOUNT   = 1295
  CURRENCY = "EUR"
  ORDER_ID = "order-abc-123"

  def test_generate_returns_hex_string
    sig = NoPayn::Signature.generate(SECRET, AMOUNT, CURRENCY, ORDER_ID)
    assert_match(/\A[0-9a-f]{64}\z/, sig)
  end

  def test_generate_is_deterministic
    sig1 = NoPayn::Signature.generate(SECRET, AMOUNT, CURRENCY, ORDER_ID)
    sig2 = NoPayn::Signature.generate(SECRET, AMOUNT, CURRENCY, ORDER_ID)
    assert_equal sig1, sig2
  end

  def test_round_trip_verify
    sig = NoPayn::Signature.generate(SECRET, AMOUNT, CURRENCY, ORDER_ID)
    assert NoPayn::Signature.verify(SECRET, AMOUNT, CURRENCY, ORDER_ID, sig)
  end

  def test_tampered_amount_fails
    sig = NoPayn::Signature.generate(SECRET, AMOUNT, CURRENCY, ORDER_ID)
    refute NoPayn::Signature.verify(SECRET, 9999, CURRENCY, ORDER_ID, sig)
  end

  def test_tampered_currency_fails
    sig = NoPayn::Signature.generate(SECRET, AMOUNT, CURRENCY, ORDER_ID)
    refute NoPayn::Signature.verify(SECRET, AMOUNT, "GBP", ORDER_ID, sig)
  end

  def test_tampered_order_id_fails
    sig = NoPayn::Signature.generate(SECRET, AMOUNT, CURRENCY, ORDER_ID)
    refute NoPayn::Signature.verify(SECRET, AMOUNT, CURRENCY, "wrong-id", sig)
  end

  def test_wrong_key_fails
    sig = NoPayn::Signature.generate(SECRET, AMOUNT, CURRENCY, ORDER_ID)
    refute NoPayn::Signature.verify("wrong-key", AMOUNT, CURRENCY, ORDER_ID, sig)
  end

  def test_invalid_signature_string_fails
    refute NoPayn::Signature.verify(SECRET, AMOUNT, CURRENCY, ORDER_ID, "not-hex")
  end

  def test_empty_signature_fails
    refute NoPayn::Signature.verify(SECRET, AMOUNT, CURRENCY, ORDER_ID, "")
  end

  def test_canonical_message_format
    # Verify the canonical message is "amount:currency:order_id"
    expected = OpenSSL::HMAC.hexdigest("SHA256", SECRET, "#{AMOUNT}:#{CURRENCY}:#{ORDER_ID}")
    actual   = NoPayn::Signature.generate(SECRET, AMOUNT, CURRENCY, ORDER_ID)
    assert_equal expected, actual
  end
end
