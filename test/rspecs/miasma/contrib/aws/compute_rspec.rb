require "miasma/contrib/aws"
require "miasma/contrib/aws/compute"

describe Miasma::Models::Compute::Aws do
  let(:response) {
    double(:response,
           code: response_code,
           headers: response_headers,
           body: response_body)
  }
  let(:response_code) { 200 }
  let(:response_headers) { {} }
  let(:response_body) { "" }
  let(:server_name) { "miasma-test-instance" }
  let(:server_id) { "server-id" }
  let(:server) {
    Miasma::Models::Compute::Server.new(
      subject, id: server_id, name: server_name,
    )
  }

  let(:subject) { described_class.new({}) }

  before { allow(subject).to receive(:make_request).and_return(response) }

  describe "#server_reload" do
    let(:response_body) { SINGLE_INSTANCE_RESPONSE }
    let(:server_id) { "i-dbec056e" }

    it "should successfully reload the server model" do
      expect(server.id).to eq(server_id)
    end

    it "should have name" do
      expect(server.name).to eq(server_name)
    end

    it "should have image_id" do
      expect(server.image_id).to eq("ami-c0e78ba0")
    end

    it "should have flavor_id" do
      expect(server.flavor_id).to eq("m1.small")
    end

    it "should have state" do
      expect(server.state).to eq(:running)
    end

    it "should have addresses_private" do
      expect(server.addresses_private.first.address).to eq("10.229.2.213")
    end

    it "should have addresses_public" do
      expect(server.addresses_public.first.address).to eq("54.177.246.39")
    end

    it "should have status" do
      expect(server.status).to eq("running")
    end

    it "should have key_name" do
      expect(server.key_name).to eq("default")
    end

    it "should not be dirty" do
      subject.server_reload(server)
      expect(server.dirty?).to be(false)
    end
  end

  describe "#server_destroy" do
    let(:response_body) { SINGLE_DESTROY_RESPONSE }

    it "should destroy the instance" do
      expect { subject.server_destroy(server) }.not_to raise_error
      expect(server.id).to be_nil
    end
  end
end

SINGLE_INSTANCE_RESPONSE = <<-EOR
<?xml version="1.0" encoding="UTF-8"?>
<DescribeInstancesResponse xmlns="http://ec2.amazonaws.com/doc/2014-06-15/">
  <requestId>b4eceb4e-ca0f-4a62-88e7-113b89bc9a4b</requestId>
  <reservationSet>
    <item>
      <reservationId>r-1538eed0</reservationId>
      <ownerId>921689585014</ownerId>
      <groupSet>
        <item>
          <groupId>sg-b5ca24f1</groupId>
          <groupName>default</groupName>
        </item>
      </groupSet>
      <instancesSet>
        <item>
          <instanceId>i-dbec056e</instanceId>
          <imageId>ami-c0e78ba0</imageId>
          <instanceState>
            <code>16</code>
            <name>running</name>
          </instanceState>
          <privateDnsName>ip-10-229-2-213.us-west-1.compute.internal</privateDnsName>
          <dnsName>ec2-54-177-246-39.us-west-1.compute.amazonaws.com</dnsName>
          <reason/>
          <keyName>default</keyName>
          <amiLaunchIndex>0</amiLaunchIndex>
          <productCodes/>
          <instanceType>m1.small</instanceType>
          <launchTime>2016-02-18T15:33:16.000Z</launchTime>
          <placement>
            <availabilityZone>us-west-1c</availabilityZone>
            <groupName/>
            <tenancy>default</tenancy>
          </placement>
          <kernelId>aki-880531cd</kernelId>
          <monitoring>
            <state>disabled</state>
          </monitoring>
          <privateIpAddress>10.229.2.213</privateIpAddress>
          <ipAddress>54.177.246.39</ipAddress>
          <groupSet>
            <item>
              <groupId>sg-b5ca24f1</groupId>
              <groupName>default</groupName>
            </item>
          </groupSet>
          <architecture>x86_64</architecture>
          <rootDeviceType>instance-store</rootDeviceType>
          <blockDeviceMapping/>
          <virtualizationType>paravirtual</virtualizationType>
          <clientToken/>
          <tagSet>
            <item>
              <key>Name</key>
              <value>miasma-test-instance</value>
            </item>
          </tagSet>
          <hypervisor>xen</hypervisor>
          <networkInterfaceSet/>
          <ebsOptimized>false</ebsOptimized>
        </item>
      </instancesSet>
    </item>
  </reservationSet>
</DescribeInstancesResponse>
EOR

SINGLE_DESTROY_RESPONSE = <<-EOR
<?xml version="1.0" encoding="UTF-8"?>
<TerminateInstancesResponse xmlns="http://ec2.amazonaws.com/doc/2014-06-15/">
  <requestId>389ddf09-79b3-4f40-a590-049e4dc2d1e0</requestId>
  <instancesSet>
    <item>
      <instanceId>i-dbec056e</instanceId>
      <currentState>
        <code>32</code>
        <name>shutting-down</name>
      </currentState>
      <previousState>
        <code>16</code>
        <name>running</name>
      </previousState>
    </item>
  </instancesSet>
</TerminateInstancesResponse>
EOR
