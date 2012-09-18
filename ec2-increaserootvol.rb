#!/usr/bin/env ruby
# == Synopsis
# This is a script that takes a nodename and increases the root vol to the
# size specified.
#
# == Usage
#
# --host (-H)
#   This is the host you want to resize.
#
# --help (-h)
#   Show this help
#
# --size (-s)
#   Set volume size in gigabytes.
#
# == Notes
#
# Sometimes overcooks the pizza.
#
# == Examples
#
#     ./ec2-increaserootvol.rb -H broker001.berkleemusic.com 
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
size = 0

# Variable Defaults
eip = nil

# Parse Options (1.8 style)
begin
   opts = GetoptLong.new(
      [ '--host',    '-H',    GetoptLong::REQUIRED_ARGUMENT ],
      [ '--help',    '-h',    GetoptLong::NO_ARGUMENT       ],
      [ '--size',    '-s',    GetoptLong::REQUIRED_ARGUMENT ]
   )

   opts.each do |opt, arg|
      case opt
         when '--host'
            host = arg
         when '--size'
            size = arg.to_i
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

if size == 0
   STDERR.puts "You either didn't pass -s or passed an empty size!"
   exit -2
end

# Instantiate ec2 obj and find node specified.
ec2 = AWS::EC2.new
instances = ec2.instances.tagged("Name").tagged_values(host)

# Die if ambiguous, if not select only instance
if instances.count > 1
   STDERR.puts "The name #{host} matches multiple ec2 instances! Exiting..."
   exit -4
end

instance = instances.first

# Die if root not EBS, then stop node
if instance.root_device_type != :ebs
   STDERR.puts "#{host} does not have an EBS volume for a root!"
   exit -5
end

begin
   printf "Stopping #{host}... "
   eip = instance.elastic_ip
   instance.stop
   printf "SUCCESS!\n"
rescue
   STDERR.puts "FAIL!"
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

# Get old root volume and detach from stopped node
oldrootatt = instance.block_device_mappings[instance.root_device_name]
oldrootvol = oldrootatt.volume

# Take snapshot of detached old root volume
printf "Taking snapshot of %s (%s) from %s...\n", instance.root_device_name, oldrootvol.id, host
STDOUT.flush

oldrootvol.detach_from instance, instance.root_device_name
oldrootsnap = oldrootvol.create_snapshot("Increasing root volume for #{host}")
printf "Snapshot: %s\n", oldrootsnap.id

until %w{:completed :error}.include? oldrootsnap.status
   sleep 5
   printf "\r"
   printf "|"
   (oldrootsnap.progress.to_i / 8).times {|i| printf "=" }
   printf "> "
   printf "%s%%", oldrootsnap.progress
   STDOUT.flush
end
printf "\n"

if oldrootsnap.status == :error
   STDERR.puts "Error creating snapshot of root for #{host}!"
   exit -7
end

# Create new volume from snapshot
begin
   printf "Creating new volume from snapshot of old root volume... "
   newrootvol = oldrootsnap.create_volume(instance.availability_zone, { :size => size })
   printf "SUCCESS!\n"
rescue
   STDERR.puts "ERROR!\n"
   exit -8
end

until %w{:available :error}.include? newrootvol.status
   printf "\r"
   printf "Waiting for new root vol to become available... "
   sleep 5
end
printf "\n"

if newrootvol.status == :error
   STDERR.puts "Error creating new volume!"
   exit -9
end

# Attach new root to instance
printf "Attaching new root vol to #{host}... "
STDOUT.flush
begin
   newrootvol.attach_to instance, instance.root_device_name
   printf "SUCCESS!\n"
rescue
   STDERR.puts "FAILURE!\n"
   exit -10
end

until %w{:error :in_use}.include? newrootvol.status
   printf "\r"
   printf "Waiting for volume to become in use..."
   sleep 5
end
printf "\n"

if newrootvol.status == :error
   STDERR.puts "Error with new root vol!"
   exit -11
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

# Resize volume, should prob use net-ssh here, this is easier for now
printf "Resizing root volume on %s...\n", host

returncode = Open4.popen4("ssh -o StrictHostKeyChecking=no #{instance.user_data} 'sudo resize2fs -f #{instance.root_device_name}' 2>&1") { |pid, stdin, stdout, stderr|
   puts stdout.gets until stdout.eof?
}

if returncode.to_i != 0
   warn "Some problems during volume resize"
end

# Clean up, delete old root snap and vol
printf "Delete old root snap and vol... "
begin
   oldrootsnap.delete
   oldrootvol.delete
   printf "SUCCESS!\n"
rescue
   printf "FAIL!\n"
end

#vim: set expandtab ts=3 sw=3:
