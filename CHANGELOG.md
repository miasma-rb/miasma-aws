# v0.2.0
* [enhancement] Properly support miasma abstract specs
* [fix] Properly handling compute instance naming
* [fix] Set load balancer as terminated when destroyed

# v0.1.36
* Fix access to default headers defined on connection

# v0.1.34
* Fix template check on update to use dirty? helper method

# v0.1.32
* Fix stack resource loading (properly load > 100 resources)
* Remove deprecated method usage on the http library
* Prevent lazy loading template on save in update context

# v0.1.30
* Hotfix: Update STS expiration check logic. Add isolated STS host override.

# v0.1.28
* Fix STS usage when building new API connections from existing connections (#21 and #23)

__Note:__ Thanks to @cixelsyd and @imbriaco for getting this sorted

# v0.1.26
* Fix broken S3 API interactions due to ordering in header modifications

# v0.1.24
* Fix token usage causing request errors
* Tune retry behavior to isolate valid retry requests
* Properly pass external ID and session name through for STS

# v0.1.22
* Fix instance profile credential auto loading
* Add support for region auto-detection when using instance profiles
* Update requests to use HTTP GET where possible for better retry support

# v0.1.20
* Fix credential loading bug (#11)

# v0.1.18
* Make aws file parsing more robust
* Fix aws config file parsing section name generation (#10)
* Add support for instance profile credentials
* Add proxy support for eucalyptus endpoints

# v0.1.16
* Add new `aws_sts_token` attribute for credentials
* Automatically include STS token on requests if available
* Add support for assuming roles via STS

# v0.1.14
* Fix checksum generation on multi-part uploads
* Fix paginated fetching of bucket objects

# v0.1.12
* Update default file paths to use `Dir.home` instead of ~ expansion
* Fix bug reading .aws/credentials when whitespace is used
* Add support for .aws/config
* Auto detect us-east-1 region and do not use custom s3 endpoint

# v0.1.10
* Fix disable rollback mapping value to on failure

# v0.1.8
* Include resource mapping for Stack
* Add support for aws credentials file
* Add stack tagging support
* Enable on failure option for stack creation
* Update list requests to use post + form to prevent param limitations via get

# v0.1.6
* Fix state assignment when undefined within orchestration stacks
* Fix multi-part S3 uploads

# v0.1.4
* Fix values set within load balancer reload
* Ensure state is valid for orchestration stack prior to set
* Load health status of instances attached to load balancers

# v0.1.2
* Migrate spec coverage
* Update storage behavior to use streamable helper

# v0.1.0
* Initial release
