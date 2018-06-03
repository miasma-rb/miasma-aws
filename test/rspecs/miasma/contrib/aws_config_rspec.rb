require "miasma/contrib/aws"

describe Miasma::Contrib::AwsApiCore::ApiCommon do
  describe "Configuration file parsing" do
    let(:klass) do
      Class.new do
        include Bogo::Lazy
        include Miasma::Contrib::AwsApiCore::ApiCommon
      end
    end

    let(:config_dir) { File.join(File.dirname(__FILE__), "aws_config") }

    it "should load the default configuration file" do
      instance = klass.new
      instance.aws_config_file = File.join(config_dir, "config.default")
      args = instance.attributes.to_smash
      instance.custom_setup(args)
      expect(args[:region]).to be_nil
      expect(args[:aws_region]).to eq("south")
      expect(args[:output]).to eq("json")
    end

    it "should load specific profile merged with default" do
      instance = klass.new
      instance.aws_config_file = File.join(config_dir, "config.multiple")
      instance.aws_profile_name = "thing2"
      args = instance.attributes.to_smash
      instance.custom_setup(args)
      expect(args[:region]).to be_nil
      expect(args[:aws_region]).to eq("north")
      expect(args[:output]).to eq("text")
      expect(args[:customized]).to eq("thing")
    end

    it "should provide useful error on malformed file" do
      instance = klass.new
      instance.aws_config_file = File.join(config_dir, "config.malformed")
      instance.aws_profile_name = "blah"
      args = instance.attributes.to_smash
      expect { instance.custom_setup(args) }.to raise_error(ArgumentError)
    end

    it "should allow comments in config" do
      instance = klass.new
      instance.aws_config_file = File.join(config_dir, "config.commented")
      args = instance.attributes.to_smash
      instance.custom_setup(args)
      expect(args[:output]).to eq("text")
      expect(args[:aws_region]).to eq("west")
      expect(args[:ignore]).to be_nil
    end

    it "should merge default config with default creds" do
      instance = klass.new
      instance.aws_config_file = File.join(config_dir, "config.default")
      instance.aws_credentials_file = File.join(config_dir, "creds.default")
      args = instance.attributes.to_smash
      instance.custom_setup(args)
      expect(args[:region]).to be_nil
      expect(args[:aws_region]).to eq("south")
      expect(args[:output]).to eq("json")
      expect(args[:aws_access_key_id]).to eq("fubar")
      expect(args[:aws_secret_access_key]).to eq("foobar")
    end

    it "should load specific profile merged with default config and creds" do
      instance = klass.new
      instance.aws_config_file = File.join(config_dir, "config.multiple")
      instance.aws_credentials_file = File.join(config_dir, "creds.multiple")
      instance.aws_profile_name = "thing2"
      args = instance.attributes.to_smash
      instance.custom_setup(args)
      expect(args[:region]).to be_nil
      expect(args[:aws_region]).to eq("north")
      expect(args[:output]).to eq("text")
      expect(args[:customized]).to eq("thing")
      expect(args[:aws_access_key_id]).to eq("BANG")
      expect(args[:aws_secret_access_key]).to eq("foobar")
    end

    it "should read quoted values and understand that the quotes are not part of the value" do
      instance = klass.new
      instance.aws_config_file = File.join(config_dir, "creds.quoted")
      args = instance.attributes.to_smash
      instance.custom_setup(args)
      expect(args[:aws_secret_access_key]).to eq("foo=bar")
    end

    it "should read aws_security_token from the file as aws_sts_token" do
      instance = klass.new
      instance.aws_config_file = File.join(config_dir, "creds.security.token")
      args = instance.attributes.to_smash
      instance.custom_setup(args)
      expect(args[:aws_sts_token]).to eq("abcd==")
    end

    it "should read aws_session_token from the file as aws_sts_token" do
      instance = klass.new
      instance.aws_config_file = File.join(config_dir, "creds.session.token")
      args = instance.attributes.to_smash
      instance.custom_setup(args)
      expect(args[:aws_sts_session_token]).to eq("abcd==")
    end

    it "should provide useful error on malformed quotes file" do
      instance = klass.new
      instance.aws_config_file = File.join(config_dir, "creds.malformed.quoted")
      args = instance.attributes.to_smash
      expect { instance.custom_setup(args) }.to raise_error(ArgumentError)
    end

    it "should load and merge files and source profile" do
      instance = klass.new
      instance.aws_config_file = File.join(config_dir, "config.multiple")
      instance.aws_credentials_file = File.join(config_dir, "creds.multiple")
      instance.aws_profile_name = "multimerge"
      args = instance.attributes.to_smash
      instance.custom_setup(args)
      expect(args[:aws_access_key_id]).to eq("BANG")
    end
  end
end
