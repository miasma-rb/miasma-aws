require 'miasma'

module Miasma
  module Contrib
    module Aws
      module Api
        class Sts < Miasma::Types::Api

          # Service name of the API
          API_SERVICE = 'sts'
          # Supported version of the AutoScaling API
          API_VERSION = '2011-06-15'

          include Contrib::AwsApiCore::ApiCommon
          include Contrib::AwsApiCore::RequestUtils

          # Assume new role
          #
          # @param role_arn [String] IAM Role ARN
          # @param args [Hash]
          # @option args [String] :external_id
          # @option args [String] :session_name
          # @return [Hash]
          def assume_role(role_arn, args={})
            req_params = Smash.new.tap do |params|
              params['Action'] = 'AssumeRole'
              params['RoleArn'] = role_arn
              params['RoleSessionName'] = args.fetch(
                :session_name,
                SecureRandom.uuid.tr('-', '')
              )
              params['ExternalId'] = args[:external_id] if args[:external_id]
            end
            result = request(
              :path => '/',
              :params => req_params
            ).get(:body, 'AssumeRoleResponse', 'AssumeRoleResult')
            Smash.new(
              :aws_sts_token => result.get('Credentials', 'SessionToken'),
              :aws_secret_access_key => result.get('Credentials', 'SecretAccessKey'),
              :aws_access_key_id => result.get('Credentials', 'AccessKeyId'),
              :aws_sts_token_expires => Time.parse(result.get('Credentials', 'Expiration')),
              :aws_sts_assumed_role_arn => result.get('AssumedRoleUser', 'Arn'),
              :aws_sts_assumed_role_id => result.get('AssumedRoleUser', 'AssumedRoleId')
            )
          end

        end
      end
    end
  end
end
