require_relative "../helper"
require "miasma/contrib/aws"

describe Miasma::Models::Compute::Aws do
  before do
    @compute = Miasma.api(
      :type => :compute,
      :provider => :aws,
      :credentials => {
        :aws_access_key_id => ENV.fetch("MIASMA_AWS_ACCESS_KEY_ID", "test-key"),
        :aws_secret_access_key => ENV.fetch("MIASMA_AWS_SECRET_ACCESS_KEY", "test-secret"),
        :aws_region => ENV.fetch("MIASMA_AWS_REGION", "us-west-1"),
      },
    )
  end

  let(:compute) { @compute }
  let(:build_args) {
    Smash.new(
      :name => "miasma-test-instance",
      :image_id => ENV.fetch("MIASMA_AWS_IMAGE", "ami-c0e78ba0"),
      :flavor_id => ENV.fetch("MIASMA_AWS_FLAVOR", "m1.small"),
      :key_name => "default",
    )
  }

  instance_exec(&MIASMA_COMPUTE_ABSTRACT)
end
