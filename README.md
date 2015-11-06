# Fluent Plugin for Amazon Kinesis producing KPL records

## Before you start...

This is a rewrite of [aws-fluent-plugin-kinesis](https://github.com/awslabs/aws-fluent-plugin-kinesis) to implement
a different shipment method using the
[KPL aggregation format](https://github.com/awslabs/amazon-kinesis-producer/blob/master/aggregation-format.md).

The basic idea is to have one PutRecord === one chunk. This has a number of advantages:

- much less complexity in plugin (less CPU/memory)
- by aggregating, we increase the throughput and decrease the cost
- since a single chunk either succeeds or fails,
  we get to use fluentd's more complex/complete retry mechanism
  (which is also exposed in the monitor). The existing retry mechanism
  has [unfortunate issues under heavy load](https://github.com/awslabs/aws-fluent-plugin-kinesis/issues/42)
- we get ordering within a chunk without having to rely on sequence
  numbers (though not overall ordering)

However, there are drawbacks:

- you have to use a KCL library to ingest
- you can't use a calculated partition key (based on the record);
  essentially, you need to use a random partition key

## Overview

[Fluentd](http://fluentd.org/) output plugin
that sends events to [Amazon Kinesis](https://aws.amazon.com/kinesis/).

## Installation

In case of using with Fluentd:
Fluentd will be also installed via the process below.

    git clone https://github.com/atlassian/fluent-plugin-kinesis-aggregation.git
    cd fluent-plugin-kinesis-aggregation
    bundle install
    rake build
    rake install

Also, you can use this plugin with td-agent:
You have to install td-agent before installing this plugin.

    git clone https://github.com/atlassian/fluent-plugin-kinesis-aggregation.git
    cd fluent-plugin-kinesis-aggregation
    bundle install
    rake build
    fluent-gem install pkg/fluent-plugin-kinesis-aggregation

Or just download specify your Ruby library path.
Below is the sample for specifying your library path via RUBYLIB.

    git clone https://github.com/atlassian/fluent-plugin-kinesis-aggregation.git
    cd fluent-plugin-kinesis-aggregation
    bundle install
    export RUBYLIB=$RUBYLIB:/path/to/fluent-plugin-kinesis-aggregation/lib

## Dependencies

 * Ruby 1.9.3+
 * Fluentd 0.10.43+

## Basic Usage

Here are general procedures for using this plugin:

 1. Install.
 1. Edit configuration
 1. Run Fluentd or td-agent

You can run this plugin with Fluentd as follows:

 1. Install.
 1. Edit configuration file and save it as 'fluentd.conf'.
 1. Then, run `fluentd -c /path/to/fluentd.conf`

To run with td-agent, it would be as follows:

 1. Install.
 1. Edit configuration file provided by td-agent.
 1. Then, run or restart td-agent.

## Configuration

Here are items for Fluentd configuration file.

To put records into Amazon Kinesis,
you need to provide AWS security credentials.
If you provide aws_key_id and aws_sec_key in configuration file as below,
we use it. You can also provide credentials via environment variables as
AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY.  Also we support IAM Role for
authentication. Please find the [AWS SDK for Ruby Developer Guide](http://docs.aws.amazon.com/AWSSdkDocsRuby/latest/DeveloperGuide/ruby-dg-setup.html)
for more information about authentication.
We support all options which AWS SDK for Ruby supports.

### type

Use the word 'kinesis-aggregation'.

### stream_name

Name of the stream to put data.

### aws_key_id

AWS access key id.

### aws_sec_key

AWS secret key.

### role_arn

IAM Role to be assumed with [AssumeRole](http://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html).
Use this option for cross account access.

### external_id

A unique identifier that is used by third parties when
[assuming roles](http://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html) in their customers' accounts.
Use this option with `role_arn` for third party cross account access.
For details, please see [How to Use an External ID When Granting Access to Your AWS Resources to a Third Party](http://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-user_externalid.html).

### region

AWS region of your stream.
It should be in form like "us-east-1", "us-west-2".
Refer to [Regions and Endpoints in AWS General Reference](http://docs.aws.amazon.com/general/latest/gr/rande.html#ak_region)
for supported regions.

### http_proxy

Proxy server, if any.
It should be in form like "http://squid:3128/"

### fixed_partition_key

Instead of using a random partition key, used a fixed one. This
forces all writes to a specific shard, and if you're using
a single thread/process will probably keep event ordering
(not recommended - watch out for hot shards!).

### detach_process

Integer. Optional. This defines the number of parallel processes to start.
This can be used to increase throughput by allowing multiple processes to
execute the plugin at once. Setting this option to > 0 will cause the plugin
to run in a separate process. The default is 0.

### num_threads

Integer. The number of threads to flush the buffer. This plugin is based on
Fluentd::BufferedOutput, so we buffer incoming records before emitting them to
Amazon Kinesis. You can find the detail about buffering mechanism [here](http://docs.fluentd.org/articles/buffer-plugin-overview).
Emitting records to Amazon Kinesis via network causes I/O Wait, so parallelizing
emitting with threads will improve throughput.

This option can be used to parallelize writes into the output(s)
designated by the output plugin. The default is 1.
Also you can use this option with *detach_process*.

### debug

Boolean. Enable if you need to debug Amazon Kinesis API call. Default is false.

## Configuration examples

Here are some configuration examles.
Assume that the JSON object below is coming to with tag 'your_tag'.

    {
      "name":"foo",
      "action":"bar"
    }

### Simply putting events to Amazon Kinesis with a partition key

In this example, a value 'foo' will be used as the partition key,
then events will be sent to the stream specified in 'stream_name'.

    <match your_tag>
    type kinesis-aggregation

    stream_name YOUR_STREAM_NAME

    aws_key_id YOUR_AWS_ACCESS_KEY
    aws_sec_key YOUR_SECRET_KEY

    region us-east-1

    fixed_partition_key foo

    # You should set the buffer_chunk_limit to substantially less
    # than the kinesis 1mb record limit, since we ship a chunk at once.
    buffer_chunk_limit 300k
    </match>

### Improving throughput to Amazon Kinesis

The achievable throughput to Amazon Kinesis is limited to single-threaded
PutRecord calls, which should be at most around 300kb each.
The plugin can also be configured to execute in parallel.
The **detach_process** and **num_threads** configuration settings control
parallelism.

In case of the configuration below, you will spawn 2 processes.

    <match your_tag>
    type kinesis

    stream_name YOUR_STREAM_NAME
    region us-east-1

    detach_process 2
    buffer_chunk_limit 300k
    </match>

You can also specify a number of threads to put.
The number of threads is bound to each individual processes.
So in this case, you will spawn 1 process which has 50 threads.

    <match your_tag>
    type kinesis

    stream_name YOUR_STREAM_NAME
    region us-east-1

    num_threads 50
    buffer_chunk_limit 300k
    </match>

Both options can be used together, in the configuration below,
you will spawn 2 processes and 50 threads per each processes.

    <match your_tag>
    type kinesis

    stream_name YOUR_STREAM_NAME
    region us-east-1

    detach_process 2
    num_threads 50
    buffer_chunk_limit 300k
    </match>

## Related Resources

* [Amazon Kinesis Developer Guide](http://docs.aws.amazon.com/kinesis/latest/dev/introduction.html)
