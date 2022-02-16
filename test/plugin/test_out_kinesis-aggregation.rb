# Copyright 2014 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You
# may not use this file except in compliance with the License. A copy of
# the License is located at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# or in the "license" file accompanying this file. This file is
# distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
# ANY KIND, either express or implied. See the License for the specific
# language governing permissions and limitations under the License.

require 'helper'

class KinesisOutputTest < Test::Unit::TestCase
  include Fluent::Test::Helpers

  def setup
    Fluent::Test.setup
  end

  CONFIG = %[
    aws_key_id test_key_id
    aws_sec_key test_sec_key
    stream_name test_stream
    region us-east-1
    fixed_partition_key test_partition_key
    buffer_chunk_limit 100k
  ]

  def create_driver(conf = CONFIG)
    Fluent::Test::Driver::Output
      .new(FluentPluginKinesisAggregation::OutputFilter).configure(conf)
  end

  def create_mock_client
    client = mock(Object.new)
    stub(Aws::Kinesis::Client).new(anything) { client }
    return client
  end

  def test_configure
    d = create_driver
    assert_equal 'test_key_id', d.instance.aws_key_id
    assert_equal 'test_sec_key', d.instance.aws_sec_key
    assert_equal 'test_stream', d.instance.stream_name
    assert_equal 'us-east-1', d.instance.region
    assert_equal 'test_partition_key', d.instance.fixed_partition_key
  end

  def test_configure_with_credentials
    d = create_driver(<<-EOS)
      profile default
      credentials_path /home/scott/.aws/credentials
      stream_name test_stream
      region us-east-1
      fixed_partition_key test_partition_key
      buffer_chunk_limit 100k
    EOS

    assert_equal 'default', d.instance.profile
    assert_equal '/home/scott/.aws/credentials', d.instance.credentials_path
    assert_equal 'test_stream', d.instance.stream_name
    assert_equal 'us-east-1', d.instance.region
    assert_equal 'test_partition_key', d.instance.fixed_partition_key
  end

  def test_configure_with_more_options
    conf = %[
      stream_name test_stream
      region us-east-1
      http_proxy http://proxy:3333/
      fixed_partition_key test_partition_key
      buffer_chunk_limit 100k
    ]
    d = create_driver(conf)
    assert_equal 'test_stream', d.instance.stream_name
    assert_equal 'us-east-1', d.instance.region
    assert_equal 'http://proxy:3333/', d.instance.http_proxy
    assert_equal 'test_partition_key', d.instance.fixed_partition_key
  end

  def test_configure_fails_on_big_chunk_limit
    conf = %[
      stream_name test_stream
      region us-east-1
      http_proxy http://proxy:3333/
      fixed_partition_key test_partition_key
      buffer_chunk_limit 1m
    ]
    assert_raise Fluent::ConfigError do
      create_driver(conf)
    end
  end

  def test_load_client
    client = stub(Object.new)
    client.put_record { {} }

    stub(Aws::Kinesis::Client).new do |options|
      assert_equal("test_key_id", options[:access_key_id])
      assert_equal("test_sec_key", options[:secret_access_key])
      assert_equal("us-east-1", options[:region])
      client
    end

    d = create_driver
    d.run(default_tag: "test")
  end

  def test_load_client_with_credentials
    client = stub(Object.new)
    client.put_record { {} }

    stub(Aws::Kinesis::Client).new do |options|
      assert_equal(nil, options[:access_key_id])
      assert_equal(nil, options[:secret_access_key])
      assert_equal("us-east-1", options[:region])

      credentials = options[:credentials]
      assert_equal("default", credentials.profile_name)
      assert_equal("/home/scott/.aws/credentials", credentials.path)

      client
    end

    d = create_driver(<<-EOS)
      profile default
      credentials_path /home/scott/.aws/credentials
      stream_name test_stream
      region us-east-1
      fixed_partition_key test_partition_key
      buffer_chunk_limit 100k
    EOS

    begin
      d.run(default_tag: "test")
    rescue Aws::Errors::NoSuchProfileError
    end
  end

  def test_load_client_with_role_arn
    client = stub(Object.new)
    client.put_record { {} }

    stub(Aws::AssumeRoleCredentials).new do |options|
      assert_equal("arn:aws:iam::001234567890:role/my-role", options[:role_arn])
      assert_equal("fluent-plugin-kinesis-aggregation", options[:role_session_name])
      assert_equal("my_external_id", options[:external_id])
      assert_equal(3600, options[:duration_seconds])
      "sts_credentials"
    end

    stub(Aws::Kinesis::Client).new do |options|
      assert_equal("sts_credentials", options[:credentials])
      client
    end

    d = create_driver(<<-EOS)
      role_arn arn:aws:iam::001234567890:role/my-role
      external_id my_external_id
      stream_name test_stream
      region us-east-1
      fixed_partition_key test_partition_key
      buffer_chunk_limit 100k
    EOS
    d.run(default_tag: "test")
  end

  def test_emitting
    d = create_driver

    data1 = {"a"=>1,"time"=>"2011-01-02T13:14:15Z","tag"=>"test"}
    data2 = {"a"=>2,"time"=>"2011-01-02T13:14:15Z","tag"=>"test"}

    time = event_time("2011-01-02 13:14:15 UTC")

    d.run(default_tag: "test") do
      client = create_mock_client
      stub.instance_of(Aws::Kinesis::Client).put_record(
        stream_name: 'test_stream',
        data: "\xF3\x89\x9A\xC2\n\x01a\n\x12test_partition_key\x1A6\b\x01\x1A2{\"a\":1,\"time\":\"2011-01-02T13:14:15Z\",\"tag\":\"test\"}\x1A6\b\x01\x1A2{\"a\":2,\"time\":\"2011-01-02T13:14:15Z\",\"tag\":\"test\"}\xA2\x0E y\x8B\x02\xDF\xAE\xAB\x93\x1C;\xCB\xAD\x1Fx".b,
        partition_key: 'test_partition_key'
      ) { {} }

      d.feed(time, data1)
      d.feed(time, data2)
    end
  end

  def test_multibyte
    d = create_driver

    data1 = {"a"=>"\xE3\x82\xA4\xE3\x83\xB3\xE3\x82\xB9\xE3\x83\x88\xE3\x83\xBC\xE3\x83\xAB","time"=>"2011-01-02T13:14:15Z".b,"tag"=>"test"}


    time = event_time("2011-01-02 13:14:15 UTC")
    d.run(default_tag: "test") do
      client = create_mock_client
      stub.instance_of(Aws::Kinesis::Client).put_record(
        stream_name: 'test_stream',
        data: "\xF3\x89\x9A\xC2\n\x01a\n\x12test_partition_key\x1AI\b\x01\x1AE{\"a\":\"\xE3\x82\xA4\xE3\x83\xB3\xE3\x82\xB9\xE3\x83\x88\xE3\x83\xBC\xE3\x83\xAB\",\"time\":\"2011-01-02T13:14:15Z\",\"tag\":\"test\"}_$\x9C\xF9v+pV:g7c\xE3\xF2$\xBA".b,
        partition_key: 'test_partition_key'
      ) { {} }

      d.feed(time, data1)
    end
  end

  def test_fail_on_bigchunk
    d = create_driver

    assert_raise(Fluent::Plugin::Buffer::BufferChunkOverflowError) do
      d.run(default_tag: "test") do
        d.feed(
          event_time("2011-01-02 13:14:15 UTC"),
          {"msg" => "z" * 1024 * 1024})
        client = dont_allow(Object.new)
        client.put_record
        mock(Aws::Kinesis::Client).new(anything) { client }
      end
    end
  end
end
