## v0.1.14
* Fix checksum generation on multi-part uploads
* Fix paginated fetching of bucket objects

## v0.1.12
* Update default file paths to use `Dir.home` instead of ~ expansion
* Fix bug reading .aws/credentials when whitespace is used
* Add support for .aws/config
* Auto detect us-east-1 region and do not use custom s3 endpoint

## v0.1.10
* Fix disable rollback mapping value to on failure

## v0.1.8
* Include resource mapping for Stack
* Add support for aws credentials file
* Add stack tagging support
* Enable on failure option for stack creation
* Update list requests to use post + form to prevent param limitations via get

## v0.1.6
* Fix state assignment when undefined within orchestration stacks
* Fix multi-part S3 uploads

## v0.1.4
* Fix values set within load balancer reload
* Ensure state is valid for orchestration stack prior to set
* Load health status of instances attached to load balancers

## v0.1.2
* Migrate spec coverage
* Update storage behavior to use streamable helper

## v0.1.0
* Initial release
