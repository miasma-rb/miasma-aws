require "miasma"
require "miasma/utils/smash"

require "time"
require "openssl"

# Miasma
module Miasma
  module Contrib
    # AWS API implementations
    module Aws
      autoload :Api, "miasma-aws/api"
    end

    # Core API for AWS access
    class AwsApiCore

      # Utility methods for API requests
      module RequestUtils

        # Fetch all results when tokens are being used
        # for paging results
        #
        # @param next_token [String]
        # @param result_key [Array<String, Symbol>] path to result
        # @yield block to perform request
        # @yieldparam options [Hash] request parameters (token information)
        # @return [Array]
        def all_result_pages(next_token, *result_key, &block)
          list = []
          options = next_token ? Smash.new("NextToken" => next_token) : Smash.new
          result = block.call(options)
          content = result.get(*result_key.dup)
          if content.is_a?(Array)
            list += content
          else
            list << content
          end
          set = result.get(*result_key.slice(0, 3))
          if set.is_a?(Hash) && set["NextToken"]
            [content].flatten.compact.each do |item|
              if item.is_a?(Hash)
                item["NextToken"] = set["NextToken"]
              end
            end
            list += all_result_pages(set["NextToken"], *result_key, &block)
          end
          list.compact
        end
      end

      # @return [String] current time ISO8601 format
      def self.time_iso8601
        Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
      end

      # HMAC helper class
      class Hmac

        # @return [OpenSSL::Digest]
        attr_reader :digest
        # @return [String] secret key
        attr_reader :key

        # Create new HMAC helper
        #
        # @param kind [String] digest type (sha1, sha256, sha512, etc)
        # @param key [String] secret key
        # @return [self]
        def initialize(kind, key)
          @digest = OpenSSL::Digest.new(kind)
          @key = key
        end

        # @return [String]
        def to_s
          "Hmac#{digest.name}"
        end

        # Generate the hexdigest of the content
        #
        # @param content [String] content to digest
        # @return [String] hashed result
        def hexdigest_of(content)
          digest << content
          hash = digest.hexdigest
          digest.reset
          hash
        end

        # Sign the given data
        #
        # @param data [String]
        # @param key_override [Object]
        # @return [Object] signature
        def sign(data, key_override = nil)
          result = OpenSSL::HMAC.digest(digest, key_override || key, data)
          digest.reset
          result
        end

        # Sign the given data and return hexdigest
        #
        # @param data [String]
        # @param key_override [Object]
        # @return [String] hex encoded signature
        def hex_sign(data, key_override = nil)
          result = OpenSSL::HMAC.hexdigest(digest, key_override || key, data)
          digest.reset
          result
        end
      end

      # Base signature class
      class Signature

        # Create new instance
        def initialize(*args)
          raise NotImplementedError.new "This class should not be used directly!"
        end

        # Generate the signature
        #
        # @param http_method [Symbol] HTTP request method
        # @param path [String] request path
        # @param opts [Hash] request options
        # @return [String] signature
        def generate(http_method, path, opts = {})
          raise NotImplementedError
        end

        # URL string escape compatible with AWS requirements
        #
        # @param string [String] string to escape
        # @return [String] escaped string
        def safe_escape(string)
          string.to_s.gsub(/([^a-zA-Z0-9_.\-~])/) do |match|
            "%" << match.unpack("H2" * match.bytesize).join("%").upcase
          end
        end
      end

      # AWS signature version 4
      class SignatureV4 < Signature

        # @return [Hmac]
        attr_reader :hmac
        # @return [String] access key
        attr_reader :access_key
        # @return [String] region
        attr_reader :region
        # @return [String] service
        attr_reader :service

        # Create new signature generator
        #
        # @param access_key [String]
        # @param secret_key [String]
        # @param region [String]
        # @param service [String]
        # @return [self]
        def initialize(access_key, secret_key, region, service)
          @hmac = Hmac.new("sha256", secret_key)
          @access_key = access_key
          @region = region
          @service = service
        end

        # Generate the signature string for AUTH
        #
        # @param http_method [Symbol] HTTP request method
        # @param path [String] request path
        # @param opts [Hash] request options
        # @return [String] signature
        def generate(http_method, path, opts)
          signature = generate_signature(http_method, path, opts)
          "#{algorithm} Credential=#{access_key}/#{credential_scope}, " \
          "SignedHeaders=#{signed_headers(opts[:headers])}, Signature=#{signature}"
        end

        # Generate URL with signed params
        #
        # @param http_method [Symbol] HTTP request method
        # @param path [String] request path
        # @param opts [Hash] request options
        # @return [String] signature
        def generate_url(http_method, path, opts)
          opts[:params].merge!(
            Smash.new(
              "X-Amz-SignedHeaders" => signed_headers(opts[:headers]),
              "X-Amz-Algorithm" => algorithm,
              "X-Amz-Credential" => "#{access_key}/#{credential_scope}",
            )
          )
          signature = generate_signature(
            http_method, path,
            opts.merge(:body => "UNSIGNED-PAYLOAD")
          )
          params = opts[:params].merge("X-Amz-Signature" => signature)
          "https://#{opts[:headers]["Host"]}/#{path}?#{canonical_query(params)}"
        end

        # Generate the signature
        #
        # @param http_method [Symbol] HTTP request method
        # @param path [String] request path
        # @param opts [Hash] request options
        # @return [String] signature
        def generate_signature(http_method, path, opts)
          to_sign = [
            algorithm,
            opts.to_smash.fetch(:headers, "X-Amz-Date", AwsApiCore.time_iso8601),
            credential_scope,
            hashed_canonical_request(
              can_req = build_canonical_request(http_method, path, opts)
            ),
          ].join("\n")
          signature = sign_request(to_sign)
        end

        # Sign the request
        #
        # @param request [String] request to sign
        # @return [String] signature
        def sign_request(request)
          key = hmac.sign(
            "aws4_request",
            hmac.sign(
              service,
              hmac.sign(
                region,
                hmac.sign(
                  Time.now.utc.strftime("%Y%m%d"),
                  "AWS4#{hmac.key}"
                )
              )
            )
          )
          hmac.hex_sign(request, key)
        end

        # @return [String] signature algorithm
        def algorithm
          "AWS4-HMAC-SHA256"
        end

        # @return [String] credential scope for request
        def credential_scope
          [
            Time.now.utc.strftime("%Y%m%d"),
            region,
            service,
            "aws4_request",
          ].join("/")
        end

        # Generate the hash of the canonical request
        #
        # @param request [String] canonical request string
        # @return [String] hashed canonical request
        def hashed_canonical_request(request)
          hmac.hexdigest_of(request)
        end

        # Build the canonical request string used for signing
        #
        # @param http_method [Symbol] HTTP request method
        # @param path [String] request path
        # @param opts [Hash] request options
        # @return [String] canonical request string
        def build_canonical_request(http_method, path, opts)
          unless path.start_with?("/")
            path = "/#{path}"
          end
          [
            http_method.to_s.upcase,
            path,
            canonical_query(opts[:params]),
            canonical_headers(opts[:headers]),
            signed_headers(opts[:headers]),
            canonical_payload(opts),
          ].join("\n")
        end

        # Build the canonical query string used for signing
        #
        # @param params [Hash] query params
        # @return [String] canonical query string
        def canonical_query(params)
          params ||= {}
          params = Hash[params.sort_by(&:first)]
          query = params.map do |key, value|
            "#{safe_escape(key)}=#{safe_escape(value)}"
          end.join("&")
        end

        # Build the canonical header string used for signing
        #
        # @param headers [Hash] request headers
        # @return [String] canonical headers string
        def canonical_headers(headers)
          headers ||= {}
          headers = Hash[headers.sort_by(&:first)]
          headers.map do |key, value|
            [key.downcase, value.chomp].join(":")
          end.join("\n") << "\n"
        end

        # List of headers included in signature
        #
        # @param headers [Hash] request headers
        # @return [String] header list
        def signed_headers(headers)
          headers ||= {}
          headers.sort_by(&:first).map(&:first).
            map(&:downcase).join(";")
        end

        # Build the canonical payload string used for signing
        #
        # @param options [Hash] request options
        # @return [String] body checksum
        def canonical_payload(options)
          body = options.fetch(:body, "")
          if options[:json]
            body = MultiJson.dump(options[:json])
          elsif options[:form]
            body = URI.encode_www_form(options[:form])
          end
          if body == "UNSIGNED-PAYLOAD"
            body
          else
            hmac.hexdigest_of(body)
          end
        end
      end

      # Common API setup
      module ApiCommon
        def self.included(klass)
          klass.class_eval do
            attribute :aws_profile_name, [FalseClass, String], :default => ENV.fetch("AWS_PROFILE", "default")
            attribute :aws_sts_token, String
            attribute :aws_sts_role_arn, String
            attribute :aws_sts_external_id, String
            attribute :aws_sts_role_session_name, String
            attribute :aws_sts_region, String
            attribute :aws_sts_host, String
            attribute :aws_sts_session_token, String
            attribute :aws_sts_session_token_code, [String, Proc, Method]
            attribute :aws_sts_mfa_serial_number, [String]
            attribute :aws_credentials_file, String,
              :required => true,
              :default => ENV.fetch("AWS_SHARED_CREDENTIALS_FILE", File.join(Dir.home, ".aws/credentials"))
            attribute :aws_config_file, String,
              :required => true,
              :default => ENV.fetch("AWS_CONFIG_FILE", File.join(Dir.home, ".aws/config"))
            attribute :aws_access_key_id, String, :required => true, :default => ENV["AWS_ACCESS_KEY_ID"]
            attribute :aws_secret_access_key, String, :required => true, :default => ENV["AWS_SECRET_ACCESS_KEY"]
            attribute :aws_iam_instance_profile, [TrueClass, FalseClass], :default => false
            attribute :aws_ecs_task_profile, [TrueClass, FalseClass], :default => false
            attribute :aws_region, String, :required => true, :default => ENV["AWS_DEFAULT_REGION"]
            attribute :aws_host, String
            attribute :aws_bucket_region, String
            attribute :api_endpoint, String, :required => true, :default => "amazonaws.com"
            attribute :euca_compat, Symbol, :allowed_values => [:path, :dns],
                                            :coerce => lambda { |v| v.is_a?(String) ? v.to_sym : v }
            attribute :euca_dns_map, Smash, :coerce => lambda { |v| v.to_smash },
                                            :default => Smash.new
            attribute :ssl_enabled, [TrueClass, FalseClass], :default => true
          end

          # AWS config file key remapping
          klass.const_set(:CONFIG_FILE_REMAP,
                          Smash.new(
            "region" => "aws_region",
            "role_arn" => "aws_sts_role_arn",
            "aws_security_token" => "aws_sts_token",
            "aws_session_token" => "aws_sts_session_token",
          ).to_smash.freeze)
          klass.const_set(:INSTANCE_PROFILE_HOST, "http://169.254.169.254".freeze)
          klass.const_set(
            :INSTANCE_PROFILE_PATH,
            "latest/meta-data/iam/security-credentials".freeze
          )
          klass.const_set(
            :INSTANCE_PROFILE_AZ_PATH,
            "latest/meta-data/placement/availability-zone".freeze
          )
          klass.const_set(:ECS_TASK_PROFILE_HOST, "http://169.254.170.2".freeze)
          klass.const_set(
            :ECS_TASK_PROFILE_PATH, ENV["AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"]
          )
        end

        # Build new API for specified type using current provider / creds
        #
        # @param type [Symbol] api type
        # @return [Api]
        def api_for(type)
          memoize(type) do
            creds = attributes.dup
            creds.delete(:aws_host)
            Miasma.api(
              Smash.new(
                :type => type,
                :provider => provider,
                :credentials => creds,
              )
            )
          end
        end

        # Provide custom setup functionality to support alternative
        # credential loading.
        #
        # @param creds [Hash]
        # @return [TrueClass]
        def custom_setup(creds)
          cred_file = load_aws_file(aws_credentials_file)
          config_file = load_aws_file(aws_config_file)
          profile = creds[:aws_profile_name]
          profile_list = [profile].compact
          new_config_creds = Smash.new
          while profile
            new_config_creds = config_file.fetch(profile, Smash.new).merge(
              new_config_creds
            )
            profile = new_config_creds.delete(:source_profile)
            profile_list << profile
          end
          new_config_creds = config_file.fetch(:default, Smash.new).merge(
            new_config_creds
          )
          profile = creds[:aws_profile_name]
          new_creds = Smash.new
          profile_list.each do |profile|
            new_creds = cred_file.fetch(profile, Smash.new).merge(
              new_creds
            )
            profile = new_creds.delete(:source_profile)
          end
          new_creds = cred_file.fetch(:default, Smash.new).merge(
            new_creds
          )
          new_creds = new_creds.merge(new_config_creds)
          # Update original data source
          creds.replace(new_creds)
          if creds[:aws_iam_instance_profile]
            self.class.const_get(:ECS_TASK_PROFILE_PATH).nil? ?
              load_instance_credentials!(creds) :
              load_ecs_credentials!(creds)
          end
          # Set underlying attributes
          data.replace(creds)
          true
        end

        # Persist any underlying stored credential data that is not a
        # defined attribute (things like STS information)
        #
        # @param creds [Hash]
        # @return [TrueClass]
        def after_setup(creds)
          skip = self.class.attributes.keys.map(&:to_s)
          creds.each do |k, v|
            k = k.to_s
            if k.start_with?("aws_") && !skip.include?(k)
              data[k] = v
            end
          end
        end

        # Attempt to load credentials from instance metadata
        #
        # @param creds [Hash]
        # @return [TrueClass]
        def load_instance_credentials!(creds)
          role = HTTP.get(
            [
              self.class.const_get(:INSTANCE_PROFILE_HOST),
              self.class.const_get(:INSTANCE_PROFILE_PATH),
              "",
            ].join("/")
          ).body.to_s.strip
          data = HTTP.get(
            [
              self.class.const_get(:INSTANCE_PROFILE_HOST),
              self.class.const_get(:INSTANCE_PROFILE_PATH),
              role,
            ].join("/")
          ).body
          unless data.is_a?(Hash)
            begin
              data = MultiJson.load(data.to_s)
            rescue MultiJson::ParseError
              data = {}
            end
          end
          creds.merge!(extract_creds(data))
          unless creds[:aws_region]
            creds[:aws_region] = get_region
          end
          true
        end

        # Attempt to load credentials from instance metadata
        #
        # @param creds [Hash]
        # @return [TrueClass]
        def load_ecs_credentials!(creds)
          # As per docs ECS_TASK_PROFILE_PATH is defined as
          # /credential_provider_version/credentials?id=task_UUID
          # where AWS fills in the version and UUID.
          # @see https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html
          data = HTTP.get(
            [
              self.class.const_get(:ECS_TASK_PROFILE_HOST),
              self.class.const_get(:ECS_TASK_PROFILE_PATH),
            ].join
          ).body
          unless data.is_a?(Hash)
            begin
              data = MultiJson.load(data.to_s)
            rescue MultiJson::ParseError
              data = {}
            end
          end
          creds.merge!(extract_creds(data))
          unless creds[:aws_region]
            creds[:aws_region] = get_region
          end
          true
        end

        # Return hash with needed information to assume role
        #
        # @param data [Hash]
        # @return [Hash]
        def extract_creds(data)
          c = Smash.new
          c[:aws_access_key_id] = data["AccessKeyId"]
          c[:aws_secret_access_key] = data["SecretAccessKey"]
          c[:aws_sts_token] = data["Token"]
          c[:aws_sts_token_expires] = Time.xmlschema(data["Expiration"])
          c[:aws_sts_role_arn] = data["RoleArn"] # used in ECS Role but not instance role
          c
        end

        # Return region from meta-data service
        #
        # @return [String]
        def get_region
          az = HTTP.get(
            [
              self.class.const_get(:INSTANCE_PROFILE_HOST),
              self.class.const_get(:INSTANCE_PROFILE_AZ_PATH),
            ].join("/")
          ).body.to_s.strip
          az.sub!(/[a-zA-Z]+$/, "")
          az
        end

        def sts_mfa_session!(creds)
          if sts_mfa_session_update_required?(creds)
            sts = Miasma::Contrib::Aws::Api::Sts.new(
              :aws_access_key_id => creds[:aws_access_key_id],
              :aws_secret_access_key => creds[:aws_secret_access_key],
              :aws_region => creds.fetch(:aws_sts_region, "us-east-1"),
              :aws_credentials_file => creds.fetch(
                :aws_credentials_file, aws_credentials_file
              ),
              :aws_config_file => creds.fetch(:aws_config_file, aws_config_file),
              :aws_profile_name => creds[:aws_profile_name],
              :aws_host => creds[:aws_sts_host],
            )
            creds.merge!(
              sts.mfa_session(
                creds[:aws_sts_session_token_code],
                :mfa_serial => creds[:aws_sts_mfa_serial_number],
              )
            )
          end
          true
        end

        # Assume requested role and replace key id and secret
        #
        # @param creds [Hash]
        # @return [TrueClass]
        def sts_assume_role!(creds)
          if sts_assume_role_update_required?(creds)
            sts = Miasma::Contrib::Aws::Api::Sts.new(
              :aws_access_key_id => get_credential(:access_key_id, creds),
              :aws_secret_access_key => get_credential(:secret_access_key, creds),
              :aws_region => creds.fetch(:aws_sts_region, "us-east-1"),
              :aws_credentials_file => creds.fetch(
                :aws_credentials_file, aws_credentials_file
              ),
              :aws_config_file => creds.fetch(:aws_config_file, aws_config_file),
              :aws_host => creds[:aws_sts_host],
              :aws_sts_token => creds[:aws_sts_session_token],
            )
            role_info = sts.assume_role(
              creds[:aws_sts_role_arn],
              :session_name => creds[:aws_sts_role_session_name],
              :external_id => creds[:aws_sts_external_id],
            )
            creds.merge!(role_info)
          end
          true
        end

        # Load configuration from the AWS configuration file
        #
        # @param file_path [String] path to configuration file
        # @return [Smash]
        def load_aws_file(file_path)
          if File.exist?(file_path)
            Smash.new.tap do |creds|
              key = :default
              File.readlines(file_path).each_with_index do |line, idx|
                line.strip!
                next if line.empty? || line.start_with?("#")
                if line.start_with?("[")
                  unless line.end_with?("]")
                    raise ArgumentError.new(
                      "Failed to parse aws file! (#{file_path} line #{idx + 1})"
                    )
                  end
                  key = line.tr("[]", "").strip.sub(/^profile /, "")
                  creds[key] = Smash.new
                else
                  unless key
                    raise ArgumentError.new(
                      "Failed to parse aws file! (#{file_path} line #{idx + 1}) " \
                      "- No section defined!"
                    )
                  end
                  line_args = line.split("=", 2).map(&:strip)
                  line_args.first.replace(
                    self.class.const_get(:CONFIG_FILE_REMAP).fetch(
                      line_args.first, line_args.first
                    )
                  )
                  if line_args.last.start_with?('"')
                    unless line_args.last.end_with?('"')
                      raise ArgumentError.new(
                        "Failed to parse aws file! (#{file_path} line #{idx + 1})"
                      )
                    end
                    line_args.last.replace(line_args.last[1..-2]) # NOTE: strip quoted values
                  end
                  begin
                    creds[key].merge!(Smash[*line_args])
                  rescue => e
                    raise ArgumentError.new(
                      "Failed to parse aws file! (#{file_path} line #{idx + 1})"
                    )
                  end
                end
              end
            end
          else
            Smash.new
          end
        end

        # Setup for API connections
        def connect
          unless aws_host
            if euca_compat
              service_name = (self.class.const_defined?(:EUCA_API_SERVICE) ?
                self.class::EUCA_API_SERVICE :
                self.class::API_SERVICE)
            else
              service_name = self.class::API_SERVICE.downcase
            end
            if euca_compat == :path
              self.aws_host = [
                api_endpoint,
                "services",
                service_name,
              ].join("/")
            elsif euca_compat == :dns && euca_dns_map[service_name]
              self.aws_host = [
                euca_dns_map[service_name],
                api_endpoint,
              ].join(".")
            else
              self.aws_host = [
                service_name,
                aws_region,
                api_endpoint,
              ].join(".")
            end
          end
        end

        # @return [Contrib::AwsApiCore::SignatureV4]
        def signer
          Contrib::AwsApiCore::SignatureV4.new(
            get_credential(:access_key_id),
            get_credential(:secret_access_key),
            aws_region,
            self.class::API_SERVICE
          )
        end

        # Return correct credential value based on STS context
        #
        # @param key [String, Symbol] credential suffix
        # @return [Object]
        def get_credential(key, data_hash = nil)
          data_hash = attributes if data_hash.nil?
          if data_hash[:aws_sts_token]
            data_hash.fetch("aws_sts_#{key}", data_hash["aws_#{key}"])
          elsif data_hash[:aws_sts_session_token]
            data_hash.fetch("aws_sts_session_#{key}", data_hash["aws_#{key}"])
          else
            data_hash["aws_#{key}"]
          end
        end

        # @return [String] custom escape for aws compat
        def uri_escape(string)
          signer.safe_escape(string)
        end

        # @return [HTTP] connection for requests (forces headers)
        def connection
          super.headers(
            "Host" => aws_host,
            "X-Amz-Date" => Contrib::AwsApiCore.time_iso8601,
          )
        end

        # @return [String] endpoint for request
        def endpoint
          "http#{"s" if ssl_enabled}://#{aws_host}"
        end

        # Override to inject signature
        #
        # @param connection [HTTP]
        # @param http_method [Symbol]
        # @param request_args [Array]
        # @return [HTTP::Response]
        def make_request(connection, http_method, request_args)
          dest, options = request_args
          path = URI.parse(dest).path
          options = options ? options.to_smash : Smash.new
          options[:headers] = Smash[connection.default_options.headers.to_a].
            merge(options.fetch(:headers, Smash.new))
          if self.class::API_VERSION
            if options[:form]
              options.set(:form, "Version", self.class::API_VERSION)
            else
              options[:params] = options.fetch(
                :params, Smash.new
              ).to_smash.deep_merge(
                Smash.new(
                  "Version" => self.class::API_VERSION,
                )
              )
            end
          end
          if aws_sts_session_token || aws_sts_session_token_code
            if sts_mfa_session_update_required?
              sts_mfa_session!(data)
            end
            options.set(:headers, "X-Amz-Security-Token", aws_sts_session_token)
          end
          if aws_sts_token || aws_sts_role_arn
            if sts_assume_role_update_required?
              sts_assume_role!(data)
            end
            options.set(:headers, "X-Amz-Security-Token", aws_sts_token)
          end
          signature = signer.generate(http_method, path, options)
          update_request(connection, options)
          options = Hash[options.map { |k, v| [k.to_sym, v] }]
          connection.auth(signature).send(http_method, dest, options)
        end

        # @return [TrueClass, FalseClass]
        # @note update check only applied if assuming role
        def sts_assume_role_update_required?(args = {})
          if args.fetch(:aws_sts_role_arn, attributes[:aws_sts_role_arn])
            expiry = args.fetch(:aws_sts_token_expires, attributes[:aws_sts_token_expires])
            expiry.nil? || expiry - 15 <= Time.now
          else
            false
          end
        end

        # @return [TrueClass, FalseClass]
        # @note update check only applied if assuming role
        def sts_mfa_session_update_required?(args = {})
          if (args.fetch(:aws_sts_session_token_code,
                         attributes[:aws_sts_session_token_code]))
            expiry = args.fetch(
              :aws_sts_session_token_expires,
              attributes[:aws_sts_session_token_expires]
            )
            expiry.nil? || expiry - 15 <= Time.now
          else
            false
          end
        end

        # Simple callback to allow request option adjustments prior to
        # signature calculation
        #
        # @param opts [Smash] request options
        # @return [TrueClass]
        def update_request(con, opts)
          true
        end

        # Determine if a retry is allowed based on exception
        #
        # @param exception [Exception]
        # @return [TrueClass, FalseClass]
        def perform_request_retry(exception)
          if exception.is_a?(Miasma::Error::ApiError)
            if [400, 500, 503].include?(exception.response.code)
              if exception.response.code == 400
                exception.response.body.to_s.downcase.include?("throttl")
              else
                true
              end
            else
              false
            end
          end
        end

        # Always allow retry
        #
        # @return [TrueClass]
        def retryable_allowed?(*_)
          true
        end
      end
    end
  end

  Models::Compute.autoload :Aws, "miasma/contrib/aws/compute"
  Models::LoadBalancer.autoload :Aws, "miasma/contrib/aws/load_balancer"
  Models::AutoScale.autoload :Aws, "miasma/contrib/aws/auto_scale"
  Models::Orchestration.autoload :Aws, "miasma/contrib/aws/orchestration"
  Models::Storage.autoload :Aws, "miasma/contrib/aws/storage"
end
