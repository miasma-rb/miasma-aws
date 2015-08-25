require 'minitest/autorun'
require 'miasma/contrib/aws'

describe Miasma::Contrib::AwsApiCore::ApiCommon do

  describe 'Configuration file parsing' do

    let(:klass) do
      Class.new do
        include Bogo::Lazy
        include Miasma::Contrib::AwsApiCore::ApiCommon
      end
    end

    let(:config_dir){ File.join(File.dirname(__FILE__), 'aws_config') }

    it 'should load the default configuration file' do
      instance = klass.new
      instance.aws_config_file = File.join(config_dir, 'config.default')
      args = instance.attributes.to_smash
      instance.custom_setup(args)
      args[:region].must_be_nil
      args[:aws_region].must_equal 'south'
      args[:output].must_equal 'json'
    end

    it 'should load specific profile merged with default' do
      instance = klass.new
      instance.aws_config_file = File.join(config_dir, 'config.multiple')
      instance.aws_profile_name = 'thing2'
      args = instance.attributes.to_smash
      instance.custom_setup(args)
      args[:region].must_be_nil
      args[:aws_region].must_equal 'north'
      args[:output].must_equal 'text'
      args[:customized].must_equal 'thing'
    end

    it 'should provide useful error on malformed file' do
      instance = klass.new
      instance.aws_config_file = File.join(config_dir, 'config.malformed')
      instance.aws_profile_name = 'blah'
      args = instance.attributes.to_smash
      ->{ instance.custom_setup(args) }.must_raise ArgumentError
    end

    it 'should allow comments in config' do
      instance = klass.new
      instance.aws_config_file = File.join(config_dir, 'config.commented')
      args = instance.attributes.to_smash
      instance.custom_setup(args)
      args[:output].must_equal 'text'
      args[:aws_region].must_equal 'west'
      args[:ignore].must_be_nil
    end

    it 'should merge default config with default creds' do
      instance = klass.new
      instance.aws_config_file = File.join(config_dir, 'config.default')
      instance.aws_credentials_file = File.join(config_dir, 'creds.default')
      args = instance.attributes.to_smash
      instance.custom_setup(args)
      args[:region].must_be_nil
      args[:aws_region].must_equal 'south'
      args[:output].must_equal 'json'
      args[:aws_access_key_id].must_equal 'fubar'
      args[:aws_secret_access_key].must_equal 'foobar'
    end

    it 'should load specific profile merged with default config and creds' do
      instance = klass.new
      instance.aws_config_file = File.join(config_dir, 'config.multiple')
      instance.aws_credentials_file = File.join(config_dir, 'creds.multiple')
      instance.aws_profile_name = 'thing2'
      args = instance.attributes.to_smash
      instance.custom_setup(args)
      args[:region].must_be_nil
      args[:aws_region].must_equal 'north'
      args[:output].must_equal 'text'
      args[:customized].must_equal 'thing'
      args[:aws_access_key_id].must_equal 'BANG'
      args[:aws_secret_access_key].must_equal 'foobar'
    end

  end

end
