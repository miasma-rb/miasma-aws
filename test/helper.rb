require 'minitest/autorun'
require 'minispec-metadata'
require 'vcr'
require 'minitest-vcr'
require 'webmock/minitest'
require 'mocha/setup'

require 'miasma'
require 'miasma/specs'

VCR.configure do |c|
  c.cassette_library_dir = 'test/cassettes'
  c.hook_into :webmock
  c.default_cassette_options = {
    :match_requests_on => [:method, :body,
      VCR.request_matchers.uri_without_params(
        'X-Amz-Date', 'X-Amz-Expires', 'X-Amz-Signature', 'X-Amz-Credential'
      )
    ]
  }
  c.filter_sensitive_data('AWS_ACCESS_KEY_ID'){ ENV['MIASMA_AWS_ACCESS_KEY_ID'] }
  c.filter_sensitive_data('AWS_SECRET_ACCESS_KEY'){ ENV['MIASMA_AWS_SECRET_ACCESS_KEY'] }
end

MinitestVcr::Spec.configure!
