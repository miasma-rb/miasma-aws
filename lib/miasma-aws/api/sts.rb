require "miasma"

module Miasma
  module Contrib
    module Aws
      module Api
        # STS helper class
        class Sts < Miasma::Types::Api

          # Service name of the API
          API_SERVICE = "sts".freeze
          # Supported version of the STS API
          API_VERSION = "2011-06-15".freeze

          include Contrib::AwsApiCore::ApiCommon
          include Contrib::AwsApiCore::RequestUtils

          # Generate MFA session credentials
          #
          # @param token_code [String, Proc] Code from MFA device
          # @param args [Hash]
          # @option args [Integer] :duration life of session in seconds
          # @option args [String] :mfa_serial MFA device identification number
          # @return [Hash]
          def mfa_session(token_code, args = {})
            req_params = Smash.new.tap do |params|
              params["Action"] = "GetSessionToken"
              params["TokenCode"] = token_code.respond_to?(:call) ? token_code.call : token_code
              params["DurationSeconds"] = args[:duration] if args[:duration]
              params["SerialNumber"] = args[:mfa_serial].to_s.empty? ? default_mfa_serial : args[:mfa_serial]
            end
            result = request(
              :path => "/",
              :params => req_params,
            ).get(:body, "GetSessionTokenResponse", "GetSessionTokenResult", "Credentials")
            Smash.new(
              :aws_sts_session_token => result["SessionToken"],
              :aws_sts_session_secret_access_key => result["SecretAccessKey"],
              :aws_sts_session_access_key_id => result["AccessKeyId"],
              :aws_sts_session_token_expires => Time.parse(result["Expiration"]),
            )
          end

          # Assume new role
          #
          # @param role_arn [String] IAM Role ARN
          # @param args [Hash]
          # @option args [String] :external_id
          # @option args [String] :session_name
          # @return [Hash]
          def assume_role(role_arn, args = {})
            req_params = Smash.new.tap do |params|
              params["Action"] = "AssumeRole"
              params["RoleArn"] = role_arn
              params["RoleSessionName"] = args[:session_name] || SecureRandom.uuid.tr("-", "")
              params["ExternalId"] = args[:external_id] if args[:external_id]
            end
            result = request(
              :path => "/",
              :params => req_params,
            ).get(:body, "AssumeRoleResponse", "AssumeRoleResult")
            Smash.new(
              :aws_sts_token => result.get("Credentials", "SessionToken"),
              :aws_sts_secret_access_key => result.get("Credentials", "SecretAccessKey"),
              :aws_sts_access_key_id => result.get("Credentials", "AccessKeyId"),
              :aws_sts_token_expires => Time.parse(result.get("Credentials", "Expiration")),
              :aws_sts_assumed_role_arn => result.get("AssumedRoleUser", "Arn"),
              :aws_sts_assumed_role_id => result.get("AssumedRoleUser", "AssumedRoleId"),
            )
          end

          # @return [String]
          def default_mfa_serial
            user_data = Iam.new(
              Smash[
                [:aws_access_key_id, :aws_secret_access_key, :aws_region].map do |key|
                  [key, attributes[key]]
                end
              ]
            ).user_info
            "arn:aws:iam::#{user_data[:account_id]}:mfa/#{user_data[:username]}"
          end
        end
      end
    end
  end
end
