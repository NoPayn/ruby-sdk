# frozen_string_literal: true

require "openssl"

module NoPayn
  module Signature
    # Canonical message: "#{amount}:#{currency}:#{order_id}"
    def self.generate(secret, amount, currency, order_id)
      message = "#{amount}:#{currency}:#{order_id}"
      OpenSSL::HMAC.hexdigest("SHA256", secret, message)
    end

    def self.verify(secret, amount, currency, order_id, signature)
      expected = generate(secret, amount, currency, order_id)
      return false unless expected.bytesize == signature.bytesize

      secure_compare(expected, signature)
    rescue ArgumentError
      false
    end

    def self.secure_compare(a, b)
      if OpenSSL.respond_to?(:fixed_length_secure_compare)
        OpenSSL.fixed_length_secure_compare(a, b)
      else
        # Manual constant-time comparison fallback
        return false unless a.bytesize == b.bytesize

        l = a.unpack("C*")
        r = b.unpack("C*")
        result = 0
        l.each_with_index { |byte, i| result |= byte ^ r[i] }
        result.zero?
      end
    rescue ArgumentError
      false
    end

    private_class_method :secure_compare
  end
end
