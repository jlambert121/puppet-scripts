#!/usr/bin/env ruby
# == Synopsis
# This is a script that takes a nodename and changes the instance type to the
# provided instance type.
#
# == Usage
#
# --host (-H)
#   This is the host you want to resize.
#
# --help (-h)
#   Show this help
#
# --type (-t)
#   Set new instance type.
#
# == Notes
#
# Sometimes overcooks the pizza.
#
# == Examples
#
#     ./ec2-increaserootvol.rb -H broker001.berkleemusic.com -t m1.large
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

require 'aws-config'
require 'getoptlong'
require 'rdoc/usage'
require 'net/http'
require 'net/ssh'
require 'open4'
require File.expand_path("~/working/git/puppet/priv/lighthouse-config")

# Show usage if no args are passed.
if ARGV.size == 0
   RDoc::usage
end

# Argument Defaults
host = ""
instancetype = ""

# Variable Defaults
eip = nil

# Parse Options (1.8 style)
begin
   opts = GetoptLong.new(
      [ '--host',    '-H',    GetoptLong::REQUIRED_ARGUMENT ],
      [ '--help',    '-h',    GetoptLong::NO_ARGUMENT       ],
      [ '--type',    '-t',    GetoptLong::REQUIRED_ARGUMENT ]
   )

   opts.each do |opt, arg|
      case opt
         when '--host'
            host = arg
         when '--type'
            instancetype = arg
         when '--help'
            RDoc::usage
      end
   end
rescue => e
   puts "Error #{$!}: #{e}"
   RDoc::usage
end

if host.empty?
   STDERR.puts "You either didn't pass -H or passed an empty host!"
   exit -1
end

if instancetype.empty?
   STDERR.puts "You either didn't pass -t or passed an empty instance type!"
   exit -2
end

# Instantiate ec2 obj and find node specified.
ec2 = AWS::EC2.new
instances = AWS.memoize { ec2.instances.select { |n| n.tags["Name"].downcase == str.downcase } }
throw "Your identifier matched multiple nodes!" if nodes.size > 1
throw "Your identifier matched no nodes!" if nodes.size == 0
instance = instances.first

# Die if -t and current instance type match
if instance.instance_type == instancetype
   STDERR.puts "#{host} is already an #{instancetype}!"
   exit -5
end

begin
   printf "Stopping #{host}... "
   eip = instance.elastic_ip
   instance.stop
rescue => e
   STDERR.puts "#{e}"
   exit -6
end

count = 0
timeout = 120

until [:stopped, :error].include? instance.status or count == timeout
   printf "\r"
   printf "Waiting for instance %s to stop...", instance.tags["Name"]
   sleep 5
   count += 5
end

if count == timeout
   STDERR.printf "Timed out waiting for instance %s (%s) to stop", host, instance.id
   exit -1
end

if instance.status == :error
   STDERR.printf "Host %s (%s) is in error state!", host, instance.id
   exit -2
end

printf "SUCCESS!\n"

begin
   instance.instance_type = instancetype
rescue => e
   STDERR.puts "#{e}"
   exit -42
end

# Start node back up, re-attach eip.
printf "Starting %s back up", host
begin
   instance.start
   until %w{:error :running}.include? instance.status
      printf "."
      sleep 5
   end
   printf "\n"

   if instance.status == :error
      throw "Error starting instance!"
   end

   unless eip.nil?
      printf "Re-attaching elastic IP... "
      instance.associate_elastic_ip(eip)
      printf "SUCCESS!\n"
   end
rescue => e
   STDERR.puts "#{e}"
end

unless eip.nil?
   # Sleep until host is available. After attaching EIP, there is typically a
   # few second delay until availability.
   printf "Waiting for box to become available at EIP...\n"
   sleep 5 until `ping -c 1 #{eip.public_ip} >/dev/null 2>&1`
end

printf "%s is back up as a %s\n", host, instance.instance_type

#vim: set expandtab ts=3 sw=3:
