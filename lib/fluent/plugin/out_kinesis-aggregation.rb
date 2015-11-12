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

require 'aws-sdk-core'
require 'yajl'
require 'logger'
require 'securerandom'
require 'digest'

require 'protocol_buffers'


# https://github.com/awslabs/amazon-kinesis-producer/blob/master/aggregation-format.md

class Tag < ProtocolBuffers::Message
  required :string, :key, 1
  optional :string, :value, 2
end

class Record < ProtocolBuffers::Message
  required :uint64, :partition_key_index, 1
  optional :uint64, :explicit_hash_key_index, 2
  required :bytes, :data, 3
  repeated Tag, :tags, 4
end

class AggregatedRecord < ProtocolBuffers::Message
  repeated :string, :partition_key_table, 1
  repeated :string, :explicit_hash_key_table, 2
  repeated Record, :records, 3
end

module FluentPluginKinesisAggregation
  class OutputFilter < Fluent::BufferedOutput

    include Fluent::DetachMultiProcessMixin
    include Fluent::SetTimeKeyMixin
    include Fluent::SetTagKeyMixin

    NAME = 'kinesis-aggregation'
    PUT_RECORD_MAX_DATA_SIZE = 1024 * 1024
    # 200 is an arbitrary number more than the envelope overhead
    # and big enough to store partition/hash key table in
    # AggregatedRecords. Note that you shouldn't really ever have
    # the buffer this high, since you're likely to fail the write
    # if anyone else is writing to the shard at the time.
    FLUENTD_MAX_BUFFER_SIZE = PUT_RECORD_MAX_DATA_SIZE - 200

    Fluent::Plugin.register_output(NAME, self)

    config_set_default :include_time_key, true
    config_set_default :include_tag_key,  true

    config_param :aws_key_id,  :string, default: nil, :secret => true
    config_param :aws_sec_key, :string, default: nil, :secret => true
    # The 'region' parameter is optional because
    # it may be set as an environment variable.
    config_param :region,      :string, default: nil

    config_param :profile,          :string, :default => nil
    config_param :credentials_path, :string, :default => nil
    config_param :role_arn,         :string, :default => nil
    config_param :external_id,      :string, :default => nil

    config_param :stream_name,            :string
    config_param :fixed_partition_key,    :string, default: nil

    config_param :debug, :bool, default: false

    config_param :http_proxy, :string, default: nil

    def configure(conf)
      super

      if @buffer.chunk_limit > FLUENTD_MAX_BUFFER_SIZE
        raise Fluent::ConfigError, "Kinesis buffer_chunk_limit is set to more than the 1mb shard limit (i.e. you won't be able to write your chunks!"
      end

      if @buffer.chunk_limit > FLUENTD_MAX_BUFFER_SIZE / 3
        log.warn 'Kinesis buffer_chunk_limit is set at more than 1/3 of the per second shard limit (1mb). This is not good if you have many producers.'
      end
    end

    def start
      detach_multi_process do
        super
        load_client
      end
    end

    def format(tag, time, record)
      return AggregatedRecord.new(
        records: [Record.new(
          partition_key_index: 0,
          data: Yajl.dump(record)
        )]
      ).to_s
    end

    def write(chunk)
      records = chunk.read
      if records.length > FLUENTD_MAX_BUFFER_SIZE
        log.error "Can't emit aggregated record of length #{records.length} (more than #{FLUENTD_MAX_BUFFER_SIZE})"
        return # do not throw, since we can't retry
      end

      partition_key = @fixed_partition_key || SecureRandom.uuid

      # confusing magic. Because of the format of protobuf records,
      # it's valid (in this case) to concatenate the AggregatedRecords
      # to form one AggregatedRecord, since we only have a repeated field
      # in records.
      message = AggregatedRecord.new(
        partition_key_table: [partition_key]
      ).to_s + records

      @client.put_record(
        stream_name: @stream_name,
        data: kpl_aggregation_pack(message),
        partition_key: partition_key
      )
    end

    private

    # https://github.com/awslabs/amazon-kinesis-producer/blob/master/aggregation-format.md
    KPL_MAGIC_NUMBER = "\xF3\x89\x9A\xC2"
    def kpl_aggregation_pack(message)
        [
          KPL_MAGIC_NUMBER, message, Digest::MD5.digest(message)
        ].pack("A4A*A16")
    end

    # This code is unchanged from https://github.com/awslabs/aws-fluent-plugin-kinesis
    def load_client
      user_agent_suffix = "fluent-#{NAME}"

      options = {
        user_agent_suffix: user_agent_suffix
      }

      if @region
        options[:region] = @region
      end

      if @aws_key_id && @aws_sec_key
        options.update(
          access_key_id: @aws_key_id,
          secret_access_key: @aws_sec_key,
        )
      elsif @profile
        credentials_opts = {:profile_name => @profile}
        credentials_opts[:path] = @credentials_path if @credentials_path
        credentials = Aws::SharedCredentials.new(credentials_opts)
        options[:credentials] = credentials
      elsif @role_arn
        credentials = Aws::AssumeRoleCredentials.new(
          client: Aws::STS::Client.new(options),
          role_arn: @role_arn,
          role_session_name: "fluent-plugin-kinesis-aggregation",
          external_id: @external_id,
          duration_seconds: 60 * 60
        )
        options[:credentials] = credentials
      end

      if @debug
        options.update(
          logger: Logger.new(log.out),
          log_level: :debug
        )
      end

      if @http_proxy
        options[:http_proxy] = @http_proxy
      end

      @client = Aws::Kinesis::Client.new(options)
    end
  end
end
