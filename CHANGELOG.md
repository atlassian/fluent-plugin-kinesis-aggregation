# CHANGELOG

## 0.4.1

- Update dependency google-protobuf to require versions newer than 3.12.0; older versions are incompatible with td-agent v4

## 0.4.0

- Update dependencies to support td-agent v4 ([td-agent v3 is EOL](https://www.fluentd.org/blog/schedule-for-td-agent-3-eol)); if you need td-agent v3 support, use 0.3.x from rubygems
- Drop testing and support for Ruby versions less than 2.7 (version embedded with td-agent v4)

## 0.3.4

- aws-sdk-kinesis 1.24 is missing a dependency from a newer version of the aws-sdk-core gem; 1.24 has been yanked and 1.24.1 has been released with the fix, but just in case 1.24 has already been installed/cached anywhere, add it to the list of excluded versions.
- Previously, we pinned google-protobuf to 3.11.x because 3.12 required Ruby >=2.5 (and td-agent ships with Ruby 2.4 embedded). google-protobuf 3.12.1 restores support for Ruby 2.3 and 2.4, so we can relax our pinning for this dependency a bit by requiring versions greater than 3.12.

## 0.3.3

- Dependency google-protobuf 3.12.0 dropped support for Ruby <2.5; td-agent3 bundles Ruby 2.4, so google-protobuf is now pinned to 3.11.x.

## 0.3.2

- Modify aws-sdk usage to require just the API/SDK resources for Kinesis
- Drop support and testing for deprecated Ruby versions (<2.3)

## 0.3.1

- Change aws-sdk usage to work with both v2 and v3
  (in particular, makes it possible to use latest td-agent which includes the s3 plugin
  and pulls in aws-sdk v3)

## 0.3.0

- Update to use fluentd 0.14 API (stick to 0.2.3 if you need support for earlier versions of fluentd)
  Much thanks to cosmo0920 for doing this.

## 0.2.3

- emit stream name in error

## 0.2.1 - 0.2.2

- update documentation to refer to published gem
- turn on testing for Ruby 2.1
- allow running on Ruby 2.1

## 0.2.0

- switch to google protobuf library (ruby native one uses too much memory)

## 0.1.1

- fix up conflict with fluent-kinesis plugin
- Changelog

## 0.1.0

- Release on Github
