#!/usr/bin/env ruby
# == Synopsis
# This is a program that automates EBS Snapshots in AWS
#
# == Usage
#
# --cleanup (-c)
#   Remove old snapshots in addition to taking snapshots
#
# --environment (-e)
#   Specify the environment in which your volumes exist  
#
# --host (-H)
#   Take snapshot of hosts root volume (EBS backed volumes)
#
# --help (-h)
#   Show this help
#
# == Notes
#  TBD 
#
# == Authors
# Bill Young <byoung2@berklee.edu>
#
# == Copyright
# 2012 The Silent Penguin LLC
#
# == License
# Licensed under GPLv2
#

require 'aws-config'

# Show usage if no args are passed.
if ARGV.size == 0
   RDoc::usage
end

# Argument defaults
cleanup     = false
environment = ""
host        = ""

# Parse Options
begin
   opts = GetoptLong.new(
      [ '--cleanup',       '-c',    GetoptLong::NO_ARGUMENT ],
      [ '--environment',   '-e',    GetoptLong::REQUIRED_ARGUMENT ],
      [ '--host',          '-H',    GetoptLong::REQUIRED_ARGUMENT ],
      [ '--help',          '-h',    GetoptLong::NO_ARGUMENT ]
   )

   opts.each do |opt, arg|
      case opt
         when '--cleanup'
            cleanup = true
         when '--environment'
            environment = arg
         when '--host'
            host = arg
         when '--help'
            RDoc::usage
      end
   end

rescue => e
   puts "Error #{$!}: #{e}"
   RDoc::usage
end
         
# Verify an environment was passed
if environment.empty? and host.empty? and cleanup == false
   fail "You either didn't pass -e or -h, not did you pass cleanup"
end

# Verify environment is a valid environment
unless environment.empty?
   unless %w{testing staging production}.include? environment
      fail "Valid environments are testing, staging, or production, not #{environment}"
   end
end

# If no host is specified, and environment is specified, take snapshots of all
# EBS volumes within given environment.
if host.empty? and not environment.empty?
   warn "No hostname was passed, taking EBS snapshots for each instance in #{environment} environment"

   # Fetch attached EBS volumes; based on environment
   all_volumes = ec2.volumes
   attachments = []
   all_volumes.each do |vol| 
      attachments << vol.attachments.select { |att| att.instance.tags["environment"] == environment }
   end

   # strip out vols not attached to anything, then flatten the array.
   attachments.delete_if { |item| item.empty? }
   attachments.flatten!
   volumes = attachments.map { |att| att.volume }

   # Create a snapshot for each volume, tagging with "Name" equal to the
   # instance name, and autodelete set to "true". Autodelete will ensure that
   # old snapshots will be reaped by the script.
   volumes.each do |vol|
      instance = vol.attachments.first.instance
      printf "Creating snapshot of volume %s", vol.id
      snap = vol.create_snapshot(Time.now.to_s)
      snap.tags["Name"] = instance.tags["Name"]
      snap.tags["autodelete"] = "true"
      until [:completed, :error].include? snap.status
         printf "."
         sleep 1
      end

      if snap.status == :completed
         printf " SUCCESS!\n"
      else
         printf " ERROR!\n"
      end
   end
elsif not host.empty? and environment.empty?
   node = ec2.instances.select do |instance|
      instance.tags["Name"] == host
   end

   if node.root_device_type != :ebs
      STDERR.puts "Requested host #{host} does not have an EBS root volume"
      exit -5
   else
      puts "Taking EBS Snapshot of #{host}"
      root_att = node.block_device_mappings[node.root_device_name]
      root_vol = root.att.volume
      snapshot = root_vol.create_snapshot("#{host}: #{Time.now}")
      until [:completed, :error].include? snapshot.status 
         printf "."
         sleep 1
      end

      if snapshot.status = :completed
         printf " SUCCESS!\n"
      else
         printf " ERROR!\n"
      end
   end
else
   unless cleanup
      fail "You passed both host and environment, doesn't make sense. One or the other."
   end
end

if cleanup
   # Clean up snapshots > 1 month old
   threshold = Time.now - (60 * 60 * 24 * 30)
   
   AWS.memoize do
      snapshots = ec2.snapshots.with_owner(:self)
      snapshots.map do |snap|
         if snap.start_time < threshold and snap.tags["autodelete"] == "true"
            p "Deleting #{snap}"
            snap.delete
         end
      end
   end
end

#vim: set expandtab ts=3 sw=3:
