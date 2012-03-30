#!/usr/bin/env ruby
# == Synopsis
# This is a small program which is to be required from any AWS script that we
# use, thereby eliminating duplicate code. It configures the AWS SDK.
#
# == Notes
# As said in the synopsis, just require aws-config. Make sure the config.yml
# is in place. If you're using our checkout, it will be or something is very
# wrong. aws-errorcodes is required in here so you won't need to in your code.
#
# == Authors
# Joe McDonagh <jmcdonagh@thesilentpenguin.com>
#
# == Copyright
# 2012 The Silent Penguin LLC
#
# == License
# Licensed under the BSD license
#

require "#{File.dirname(__FILE__)}/aws-errorcodes"
require 'rubygems'
require 'yaml'
require 'aws-sdk'

# Load AWS config
begin
   config = YAML.load(File.read("config.yml"))
rescue => e
   STDERR.puts "Error loading YAML config: #{e}"
   exit ECFGREAD
end

unless config.kind_of?(Hash)
  puts <<END
config.yml is formatted incorrectly.  Please use the following format:

access_key_id: YOUR_ACCESS_KEY_ID
secret_access_key: YOUR_SECRET_ACCESS_KEY

END
  exit ECFGFORMAT
end

AWS.config(config)

#vim: set expandtab ts=3 sw=3:
