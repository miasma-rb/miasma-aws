require_relative "../helper"
require "miasma/contrib/aws"

describe Miasma::Models::Storage::Aws do
  before do
    @storage = Miasma.api(
      :type => :storage,
      :provider => :aws,
      :credentials => {
        :aws_access_key_id => ENV.fetch("MIASMA_AWS_ACCESS_KEY_ID", "test-key"),
        :aws_secret_access_key => ENV.fetch("MIASMA_AWS_SECRET_ACCESS_KEY", "test-secret"),
        :aws_region => ENV.fetch("MIASMA_AWS_REGION", "us-west-1"),
      },
    )
  end

  let(:storage) { @storage }

  instance_exec(&MIASMA_STORAGE_ABSTRACT)
end
