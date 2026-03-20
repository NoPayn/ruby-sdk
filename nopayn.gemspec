# frozen_string_literal: true

require_relative "lib/nopayn/version"

Gem::Specification.new do |spec|
  spec.name          = "nopayn"
  spec.version       = NoPayn::VERSION
  spec.authors       = ["Cost+"]
  spec.email         = ["dev@costplus.io"]

  spec.summary       = "Ruby SDK for the NoPayn Payment Gateway"
  spec.description   = "Official Ruby SDK for the NoPayn Payment Gateway. " \
                        "Simplifies the HPP redirect flow, HMAC payload signing, " \
                        "and webhook verification."
  spec.homepage      = "https://github.com/NoPayn/ruby-sdk"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.1"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"]   = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir["lib/**/*.rb", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "net-http"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "webmock", "~> 3.0"
end
