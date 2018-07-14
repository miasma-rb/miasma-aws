require "miasma/contrib/aws"

describe Miasma::Contrib::AwsApiCore::Hmac do
  let(:kind) { "sha1" }
  let(:key) { "key" }
  let(:instance) { described_class.new(kind, key) }

  describe "#to_s" do
    it "should provide hmac type" do
      expect(instance.to_s).to eq("HmacSHA1")
    end
  end

  describe "#sign" do
    it "should return signed string" do
      expect(instance.sign("data")).to be_a(String)
    end

    it "should convert data to string" do
      expect(instance.sign([1, 2])).to be_a(String)
    end

    it "should use key override when provided" do
      o_key = "override"
      expect(OpenSSL::HMAC).to receive(:digest).with(
        anything, o_key, anything
      )
      instance.sign("data", o_key)
    end

    context "when key is unset" do
      let(:key) { nil }

      it "should raise error" do
        expect { instance.sign("data") }.to raise_error(ArgumentError)
      end
    end
  end
end
