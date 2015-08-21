# Miasma AWS

AWS API plugin for the miasma cloud library

## Supported credential attributes:

Supported attributes used in the credentials section of API
configurations:

```ruby
Miasma.api(
  :type => :storage,
  :provider => :aws,
  :credentials => {
    ...
  }
)
```

### Common general use attributes

* `aws_access_key_id` - User access key ID
* `aws_secret_access_key` - User secret access key
* `aws_region` - Region to connect

### Profile related attributes

* `aws_profile_name` - Use credentials/configuration from profile name
* `aws_credentials_file` - Specify custom credentials file
* `aws_config_file` - Specify custom configuration file

### Secure Token Service related:

* `aws_sts_token` - Set STS token to use with current key ID and secret
* `aws_sts_role_arn` - Assume role
* `aws_external_id` - Provide an external ID when assuming role
* `aws_sts_role_session_name` - Provide custom session name when assuming role

### S3 related attributes

* `aws_bucket_region` - Override current `aws_region` for bucket

### Other attributes

* `aws_host` - Provide customized full endpoint (without http/https) for API requests
* `api_endpoint` - Use custom endpoint when constructing (defaults to 'amazonaws.com')
* `euca_compat`- Enable compatibility mode for eucalyptus. Allowed values:
  * `path` - Construct using `services/SERVICE_NAME`
  * `dns` - Construct using DNS subdomains (`SERVICE_NAME.REGION.API_ENDPOINT` by default)
* `euca_dns_map` - Map services to custom DNS subdomains
* `ssl_enabled` - Use SSL for API connections

## Current support matrix

|Model         |Create|Read|Update|Delete|
|--------------|------|----|------|------|
|AutoScale     |  X   | X  |      |      |
|BlockStorage  |      |    |      |      |
|Compute       |  X   | X  |      |  X   |
|DNS           |      |    |      |      |
|LoadBalancer  |  X   | X  |  X   |  X   |
|Network       |      |    |      |      |
|Orchestration |  X   | X  |  X   |  X   |
|Queues        |      |    |      |      |
|Storage       |  X   | X  |  X   |  X   |

## Info
* Repository: https://github.com/miasma-rb/miasma-aws
