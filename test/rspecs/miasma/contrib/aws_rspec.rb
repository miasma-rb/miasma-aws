require "miasma/contrib/aws"

describe Miasma::Contrib::AwsApiCore::ApiCommon do
  let(:klass) do
    Class.new do
      include Bogo::Lazy
      include Miasma::Contrib::AwsApiCore::ApiCommon
    end
  end

  let(:instance) { klass.new }

  describe "#sts_assume_role_update_required?" do
    let(:aws_sts_role_arn) { "ARN" }
    let(:aws_sts_token_expires) { Time.now + 700 }

    context "with role arn set in attributes" do
      before do
        instance.aws_sts_role_arn = aws_sts_role_arn
        instance.data[:aws_sts_token_expires] = aws_sts_token_expires
      end

      it "should be false when token has not expired" do
        expect(instance.sts_assume_role_update_required?).to be_falsey
      end

      context "when role arn is unset" do
        let(:aws_sts_role_arn) { nil }

        it "should be false" do
          expect(instance.sts_assume_role_update_required?).to be_falsey
        end
      end

      context "when token has expired" do
        let(:aws_sts_token_expires) { Time.now - 1 }

        it "should be true" do
          expect(instance.sts_assume_role_update_required?).to be_truthy
        end
      end

      context "when expiry argument is provided" do
        it "use value in arguments" do
          expect(instance.sts_assume_role_update_required?(
            :aws_sts_token_expires => Time.now - 1,
          )).to be_truthy
        end
      end
    end
  end

  describe "#sts_mfa_session_update_required?" do
    let(:aws_sts_session_token_code) { "CODE" }
    let(:aws_sts_session_token_expires) { Time.now + 700 }

    context "with role arn set in attributes" do
      before do
        instance.aws_sts_session_token_code = aws_sts_session_token_code
        instance.data[:aws_sts_session_token_expires] = aws_sts_session_token_expires
      end

      it "should be false when token has not expired" do
        expect(instance.sts_mfa_session_update_required?).to be_falsey
      end

      context "when session token code is unset" do
        let(:aws_sts_session_token_code) { nil }

        it "should be false" do
          expect(instance.sts_mfa_session_update_required?).to be_falsey
        end
      end

      context "when token has expired" do
        let(:aws_sts_session_token_expires) { Time.now - 1 }

        it "should be true" do
          expect(instance.sts_mfa_session_update_required?).to be_truthy
        end
      end

      context "when expiry argument is provided" do
        it "use value in arguments" do
          expect(instance.sts_mfa_session_update_required?(
            :aws_sts_session_token_expires => Time.now - 1,
          )).to be_truthy
        end
      end
    end
  end
end
