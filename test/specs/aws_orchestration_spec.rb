require_relative '../helper'
require 'miasma/contrib/aws'

describe Miasma::Models::Orchestration::Aws do

  before do
    @orchestration = Miasma.api(
      :type => :orchestration,
      :provider => :aws,
      :credentials => {
        :aws_access_key_id => ENV.fetch('MIASMA_AWS_ACCESS_KEY_ID', 'test-key'),
        :aws_secret_access_key => ENV.fetch('MIASMA_AWS_SECRET_ACCESS_KEY', 'test-secret'),
        :aws_region => ENV.fetch('MIASMA_AWS_REGION', 'us-west-1')
      }
    )
  end

  let(:orchestration){ @orchestration }
  let(:build_args){
    Smash.new(
      :name => 'miasma-test-stack',
      :template => {
        'AWSTemplateFormatVersion' => '2010-09-09',
        'Description' => 'Miasma test stack',
        'Resources' => {
          'MiasmaTestHandle' => {
            'Type' => 'AWS::CloudFormation::WaitConditionHandle'
          }
        }
      },
      :parameters => {
      }
    )
  }

  instance_exec(&MIASMA_ORCHESTRATION_ABSTRACT)

end
