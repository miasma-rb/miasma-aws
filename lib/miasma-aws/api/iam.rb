require 'miasma'

module Miasma
  module Contrib
    module Aws
      module Api
        class Iam < Miasma::Types::Api

          # Service name of the API
          API_SERVICE = 'iam'
          # Supported version of the IAM API
          API_VERSION = '2010-05-08'

          include Contrib::AwsApiCore::ApiCommon
          include Contrib::AwsApiCore::RequestUtils

          def connect
            super
            service_name = self.class::API_SERVICE.downcase
            self.aws_host = [
              service_name,
              api_endpoint
            ].join('.')
          end

          # Fetch current user information
          def user_info
            result = request(
              :path => '/',
              :params => {
                'Action' => 'GetUser'
              }
            ).get(:body, 'GetUserResponse', 'GetUserResult', 'User')
            Smash.new(
              :user_id => result['UserId'],
              :path => result['Path'],
              :username => result['UserName'],
              :arn => result['Arn'],
              :created => result['CreateDate'],
              :password_last_used => result['PasswordLastUsed'],
              :account_id => result['Arn'].split(':')[4]
            )
          end

        end
      end
    end
  end
end
