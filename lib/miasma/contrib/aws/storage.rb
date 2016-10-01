require 'stringio'
require 'xmlsimple'
require 'miasma'

module Miasma
  module Models
    class Storage
      # AWS storage API
      class Aws < Storage

        # Service name of the API
        API_SERVICE = 's3'.freeze
        # Service name of the API in eucalyptus
        EUCA_API_SERVICE = 'objectstorage'.freeze
        # Supported version of the Storage API
        API_VERSION = '2006-03-01'.freeze

        include Contrib::AwsApiCore::ApiCommon
        include Contrib::AwsApiCore::RequestUtils

        # Fetch all results when tokens are being used
        # for paging results
        #
        # @param next_token [String]
        # @param result_key [Array<String, Symbol>] path to result
        # @yield block to perform request
        # @yieldparam options [Hash] request parameters (token information)
        # @return [Array]
        # @note this is customized to S3 since its API is slightly
        #   different than the usual token based fetching
        def all_result_pages(next_token, *result_key, &block)
          list = []
          options = next_token ? Smash.new('marker' => next_token) : Smash.new
          result = block.call(options)
          content = result.get(*result_key.dup)
          if(content.is_a?(Array))
            list += content
          else
            list << content
          end
          set = result.get(*result_key.slice(0, 2))
          if(set.is_a?(Hash) && set['IsTruncated'] && set['Contents'])
            content_key = (
              set['Contents'].respond_to?(:last) ? set['Contents'].last : set['Contents']
            )['Key']
            list += all_result_pages(content_key, *result_key, &block)
          end
          list.compact
        end

        # Simple init override to force HOST and adjust region for
        # signatures if required
        def initialize(args)
          args = args.to_smash
          cache_region = args[:aws_region]
          args[:aws_region] = args.fetch(:aws_bucket_region, 'us-east-1')
          super(args)
          aws_region = cache_region
          if(aws_bucket_region && aws_bucket_region != 'us-east-1')
            self.aws_host = "s3-#{aws_bucket_region}.amazonaws.com"
          else
            self.aws_host = 's3.amazonaws.com'
          end
        end

        # Save bucket
        #
        # @param bucket [Models::Storage::Bucket]
        # @return [Models::Storage::Bucket]
        def bucket_save(bucket)
          unless(bucket.persisted?)
            req_args = Smash.new(
              :method => :put,
              :path => '/',
              :endpoint => bucket_endpoint(bucket)
            )
            if(aws_bucket_region)
              req_args[:body] = XmlSimple.xml_out(
                Smash.new(
                  'CreateBucketConfiguration' => {
                    'LocationConstraint' => aws_bucket_region
                  }
                ),
                'AttrPrefix' => true,
                'KeepRoot' => true
              )
              req_args[:headers] = Smash.new(
                'Content-Length' => req_args[:body].size.to_s
              )
            end
            request(req_args)
            bucket.id = bucket.name
            bucket.valid_state
          end
          bucket
        end

        # Directly fetch bucket
        #
        # @param ident [String] identifier
        # @return [Models::Storage::Bucket, NilClass]
        def bucket_get(ident)
          bucket = Bucket.new(self,
            :id => ident,
            :name => ident
          )
          begin
            bucket.reload
            bucket
          rescue Error::ApiError::RequestError => e
            if(e.response.status == 404)
              nil
            else
              raise
            end
          end
        end

        # Destroy bucket
        #
        # @param bucket [Models::Storage::Bucket]
        # @return [TrueClass, FalseClass]
        def bucket_destroy(bucket)
          if(bucket.persisted?)
            request(
              :path => '/',
              :method => :delete,
              :endpoint => bucket_endpoint(bucket),
              :expects => 204
            )
            true
          else
            false
          end
        end

        # Reload the bucket
        #
        # @param bucket [Models::Storage::Bucket]
        # @return [Models::Storage::Bucket]
        def bucket_reload(bucket)
          if(bucket.persisted?)
            begin
              result = request(
                :path => '/',
                :method => :head,
                :endpoint => bucket_endpoint(bucket)
              )
            rescue Error::ApiError::RequestError => e
              if(e.response.status == 404)
                bucket.data.clear
                bucket.dirty.clear
              else
                raise
              end
            end
          end
          bucket
        end

        # Custom bucket endpoint
        #
        # @param bucket [Models::Storage::Bucket]
        # @return [String]
        # @todo properly escape bucket name
        def bucket_endpoint(bucket)
          ::File.join(endpoint, bucket.name)
        end

        # Return all buckets
        #
        # @return [Array<Models::Storage::Bucket>]
        def bucket_all
          result = all_result_pages(nil, :body, 'ListAllMyBucketsResult', 'Buckets', 'Bucket') do |options|
            request(
              :path => '/',
              :params => options
            )
          end
          result.map do |bkt|
            Bucket.new(
              self,
              :id => bkt['Name'],
              :name => bkt['Name'],
              :created => bkt['CreationDate']
            ).valid_state
          end
        end

        # Return filtered files
        #
        # @param args [Hash] filter options
        # @return [Array<Models::Storage::File>]
        def file_filter(bucket, args)
          if(args[:prefix])
            result = request(
              :path => '/',
              :endpoint => bucket_endpoint(bucket),
              :params => Smash.new(
                :prefix => args[:prefix]
              )
            )
            [result.get(:body, 'ListBucketResult', 'Contents')].flatten.compact.map do |file|
              File.new(
                bucket,
                :id => ::File.join(bucket.name, file['Key']),
                :name => file['Key'],
                :updated => file['LastModified'],
                :size => file['Size'].to_i
              ).valid_state
            end
          else
            bucket_all
          end
        end

        # Return all files within bucket
        #
        # @param bucket [Bucket]
        # @return [Array<File>]
        def file_all(bucket)
          result = all_result_pages(nil, :body, 'ListBucketResult', 'Contents') do |options|
            request(
              :path => '/',
              :params => options,
              :endpoint => bucket_endpoint(bucket)
            )
          end
          result.map do |file|
            File.new(
              bucket,
              :id => ::File.join(bucket.name, file['Key']),
              :name => file['Key'],
              :updated => file['LastModified'],
              :size => file['Size'].to_i
            ).valid_state
          end
        end

        # Save file
        #
        # @param file [Models::Storage::File]
        # @return [Models::Storage::File]
        def file_save(file)
          if(file.dirty?)
            file.load_data(file.attributes)
            args = Smash.new
            headers = Smash[
              Smash.new(
                :content_type => 'Content-Type',
                :content_disposition => 'Content-Disposition',
                :content_encoding => 'Content-Encoding'
              ).map do |attr, key|
                if(file.attributes[attr])
                  [key, file.attributes[attr]]
                end
              end.compact
            ]
            unless(headers.empty?)
              args[:headers] = headers
            end
            if(file.attributes[:body].respond_to?(:read) &&
              file.attributes[:body].size >= Storage::MAX_BODY_SIZE_FOR_STRINGIFY)
              upload_id = request(
                args.merge(
                  Smash.new(
                    :method => :post,
                    :path => file_path(file),
                    :endpoint => bucket_endpoint(file.bucket),
                    :params => {
                      :uploads => true
                    }
                  )
                )
              ).get(:body, 'InitiateMultipartUploadResult', 'UploadId')
              begin
                count = 1
                parts = []
                file.body.rewind
                while(content = file.body.read(Storage::READ_BODY_CHUNK_SIZE * 1.5))
                  parts << [
                    count,
                    request(
                      :method => :put,
                      :path => file_path(file),
                      :endpoint => bucket_endpoint(file.bucket),
                      :headers => Smash.new(
                        'Content-Length' => content.size,
                        'Content-MD5' => Digest::MD5.base64digest(content)
                      ),
                      :params => Smash.new(
                        'partNumber' => count,
                        'uploadId' => upload_id
                      ),
                      :body => content
                    ).get(:headers, :etag)
                  ]
                  count += 1
                end
                complete = XmlSimple.xml_out(
                  Smash.new(
                    'CompleteMultipartUpload' => {
                      'Part' => parts.map{|part|
                        {'PartNumber' => part.first, 'ETag' => part.last}
                      }
                    }
                  ),
                  'AttrPrefix' => true,
                  'KeepRoot' => true
                )
                result = request(
                  :method => :post,
                  :path => file_path(file),
                  :endpoint => bucket_endpoint(file.bucket),
                  :params => Smash.new(
                    'uploadId' => upload_id
                  ),
                  :headers => Smash.new(
                    'Content-Length' => complete.size
                  ),
                  :body => complete
                )
                file.etag = result.get(:body, 'CompleteMultipartUploadResult', 'ETag')
              rescue => e
                request(
                  :method => :delete,
                  :path => file_path(file),
                  :endpoint => bucket_endpoint(file.bucket),
                  :params => {
                    'uploadId' => upload_id
                  },
                  :expects => 204
                )
                raise
              end
            else
              if(file.attributes[:body].respond_to?(:readpartial))
                args.set(:headers, 'Content-Length', file.body.size.to_s)
                file.body.rewind
                args[:body] = file.body.readpartial(file.body.size)
                file.body.rewind
              else
                args.set(:headers, 'Content-Length', 0)
              end
              result = request(
                args.merge(
                  Smash.new(
                    :method => :put,
                    :path => file_path(file),
                    :endpoint => bucket_endpoint(file.bucket)
                  )
                )
              )
              file.etag = result.get(:headers, :etag)
            end
            file.id = ::File.join(file.bucket.name, file.name)
            file.valid_state
          end
          file
        end

        # Destroy file
        #
        # @param file [Models::Storage::File]
        # @return [TrueClass, FalseClass]
        def file_destroy(file)
          if(file.persisted?)
            request(
              :method => :delete,
              :path => file_path(file),
              :endpoint => bucket_endpoint(file.bucket),
              :expects => 204
            )
            true
          else
            false
          end
        end

        # Reload the file
        #
        # @param file [Models::Storage::File]
        # @return [Models::Storage::File]
        def file_reload(file)
          if(file.persisted?)
            name = file.name
            result = request(
              :path => file_path(file),
              :endpoint => bucket_endpoint(file.bucket)
            )
            file.data.clear && file.dirty.clear
            info = result[:headers]
            file.load_data(
              :id => ::File.join(file.bucket.name, name),
              :name => name,
              :updated => info[:last_modified],
              :etag => info[:etag],
              :size => info[:content_length].to_i,
              :content_type => info[:content_type]
            ).valid_state
          end
          file
        end

        # Create publicly accessible URL
        #
        # @param timeout_secs [Integer] seconds available
        # @return [String] URL
        def file_url(file, timeout_secs)
          if(file.persisted?)
            signer.generate_url(
              :get, ::File.join(uri_escape(file.bucket.name), file_path(file)),
              :headers => Smash.new(
                'Host' => aws_host
              ),
              :params => Smash.new(
                'X-Amz-Date' => Contrib::AwsApiCore.time_iso8601,
                'X-Amz-Expires' => timeout_secs
              )
            )
          else
            raise Error::ModelPersistError.new "#{file} has not been saved!"
          end
        end

        # Fetch the contents of the file
        #
        # @param file [Models::Storage::File]
        # @return [IO, HTTP::Response::Body]
        def file_body(file)
          file_content = nil
          if(file.persisted?)
            result = request(
              :path => file_path(file),
              :endpoint => bucket_endpoint(file.bucket),
              :disable_body_extraction => true
            )
            content = result[:body]
            begin
              if(content.is_a?(String))
                file_content = StringIO.new(content)
              else
                if(content.respond_to?(:stream!))
                  content.stream!
                end
                file_content = content
              end
            rescue HTTP::StateError
              file_content = StringIO.new(content.to_s)
            end
          else
            file_content = StringIO.new('')
          end
          File::Streamable.new(file_content)
        end

        # Simple callback to allow request option adjustments prior to
        # signature calculation
        #
        # @param opts [Smash] request options
        # @return [TrueClass]
        # @note this only updates when :body is defined. if a :post is
        # happening (which implicitly forces :form) or :json is used
        # it will not properly checksum. (but that's probably okay)
        def update_request(con, opts)
          opts[:headers]['x-amz-content-sha256'] = Digest::SHA256.
            hexdigest(opts.fetch(:body, ''))
          true
        end

        # @return [String] escaped file path
        def file_path(file)
          file.name.split('/').map do |part|
            uri_escape(part)
          end.join('/')
        end

      end
    end
  end
end
