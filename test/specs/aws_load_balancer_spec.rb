require_relative "../helper"
require "miasma/contrib/aws"

describe Miasma::Models::LoadBalancer::Aws do
  before do
    @load_balancer = Miasma.api(
      :type => :load_balancer,
      :provider => :aws,
      :credentials => {
        :aws_access_key_id => ENV.fetch("MIASMA_AWS_ACCESS_KEY_ID", "test-key"),
        :aws_secret_access_key => ENV.fetch("MIASMA_AWS_SECRET_ACCESS_KEY", "test-secret"),
        :aws_region => ENV.fetch("MIASMA_AWS_REGION", "us-west-1"),
      },
    )
  end

  let(:load_balancer) { @load_balancer }
  let(:build_args) {
    Smash.new(
      :name => "miasma-test-load-balancer",
      :listeners => [
        :load_balancer_port => 80,
        :instance_port => 80,
        :protocol => "HTTP",
        :instance_protocol => "HTTP",
      ],
    )
  }

  instance_exec(&MIASMA_LOAD_BALANCER_ABSTRACT)
end
