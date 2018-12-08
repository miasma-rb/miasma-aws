require "miasma/contrib/aws"

describe Miasma::Contrib::AwsApiCore::ApiCommon do
  let(:klass) do
    Class.new do
      include Bogo::Lazy
      include Miasma::Contrib::AwsApiCore::ApiCommon

      def self.name
        "MiasmaTest"
      end

      def initialize(args = {})
        custom_setup(args)
        load_data(args)
        after_setup(args)
      end
    end
  end

  let(:config_dir) { File.join(File.dirname(__FILE__), "aws_config") }

  before do
    allow(ENV).to receive(:[]).and_return(nil)
    allow(ENV).to receive(:fetch) { |_, v| v }
    allow(ENV).to receive(:fetch).with("AWS_SHARED_CREDENTIALS_FILE", anything).and_return("UNSET_CREDS_FILE")
    allow(ENV).to receive(:fetch).with("AWS_CONFIG_FILE", anything).and_return("UNSET_CONFIG_FILE")
  end

  describe "Configuration file parsing" do
    it "should load the default configuration file" do
      instance = klass.new(
        aws_config_file: File.join(config_dir, "config.default"),
      )
      expect(instance.aws_region).to eq("south")
      expect(instance.data[:aws_output]).to eq("json")
    end

    it "should load specific profile merged with default" do
      instance = klass.new(
        aws_config_file: File.join(config_dir, "config.multiple"),
        aws_profile_name: "thing2",
      )
      expect(instance.aws_region).to eq("north")
      expect(instance.data[:aws_output]).to eq("text")
      expect(instance.data[:aws_customized]).to eq("thing")
    end

    it "should provide useful error on malformed file" do
      expect {
        instance = klass.new(
          aws_config_file: File.join(config_dir, "config.malformed"),
          aws_profile_name: "blah",
        )
      }.to raise_error(ArgumentError)
    end

    it "should allow comments in config" do
      instance = klass.new(
        aws_config_file: File.join(config_dir, "config.commented"),
      )
      expect(instance.aws_region).to eq("west")
      expect(instance.data[:aws_output]).to eq("text")
      expect(instance.data[:aws_ignore]).to be_nil
    end

    it "should merge default config with default creds" do
      instance = klass.new(
        aws_config_file: File.join(config_dir, "config.default"),
        aws_credentials_file: File.join(config_dir, "creds.default"),
      )
      expect(instance.aws_region).to eq("south")
      expect(instance.data[:aws_output]).to eq("json")
      expect(instance.aws_access_key_id).to eq("fubar")
      expect(instance.aws_secret_access_key).to eq("foobar")
    end

    it "should load specific profile merged with default config and creds" do
      instance = klass.new(
        aws_config_file: File.join(config_dir, "config.multiple"),
        aws_credentials_file: File.join(config_dir, "creds.multiple"),
        aws_profile_name: "thing2",
      )
      expect(instance.aws_region).to eq("north")
      expect(instance.data[:aws_output]).to eq("text")
      expect(instance.data[:aws_customized]).to eq("thing")
      expect(instance.aws_access_key_id).to eq("BANG")
      expect(instance.aws_secret_access_key).to eq("foobar")
    end

    it "should read quoted values and understand that the quotes are not part of the value" do
      instance = klass.new(
        aws_config_file: File.join(config_dir, "creds.quoted"),
      )
      expect(instance.aws_secret_access_key).to eq("foo=bar")
    end

    it "should read aws_security_token from the file as aws_sts_token" do
      instance = klass.new(
        aws_config_file: File.join(config_dir, "creds.security.token"),
      )
      expect(instance.aws_sts_token).to eq("abcd==")
    end

    it "should read aws_session_token from the file as aws_sts_token" do
      instance = klass.new(
        aws_config_file: File.join(config_dir, "creds.session.token"),
      )
      expect(instance.aws_sts_session_token).to eq("abcd==")
    end

    it "should provide useful error on malformed quotes file" do
      expect {
        instance = klass.new(
          aws_config_file: File.join(config_dir, "creds.malformed.quoted"),
        )
      }.to raise_error(ArgumentError)
    end

    it "should load and merge files and source profile" do
      instance = klass.new(
        aws_config_file: File.join(config_dir, "config.multiple"),
        aws_credentials_file: File.join(config_dir, "creds.multiple"),
        aws_profile_name: "multimerge",
      )
      expect(instance.aws_access_key_id).to eq("BANG")
    end
  end

  describe "default value overrides" do
    let(:default_id) { "DEFAULT_ID" }

    before do
      expect(ENV).to receive(:[]).with("AWS_ACCESS_KEY_ID").and_return(default_id)
    end

    it "should return default id value by default" do
      instance = klass.new
      expect(instance.aws_access_key_id).to eq(default_id)
    end

    it "should use value from configuration file" do
      instance = klass.new(
        aws_credentials_file: File.join(config_dir, "creds.default"),
      )
      expect(instance.aws_access_key_id).to eq("fubar")
    end

    it "should use set value" do
      instance = klass.new(
        aws_credentials_file: File.join(config_dir, "creds.default"),
        aws_access_key_id: "override",
      )
      expect(instance.aws_access_key_id).to eq("override")
    end
  end
end
