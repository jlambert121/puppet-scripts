#!/usr/bin/env ruby
# == Synopsis
# This is a program that automates EBS Snapshots in AWS
#
# == Usage
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
environment = ""
host        = ""

# Parse Options
begin
   opts = GetoptLong.new(
      [ '--environment',   '-e',    GetoptLong::REQUIRED_ARGUMENT ],
      [ '--host',          '-H',    GetoptLong::OPTIONAL_ARGUMENT ],
      [ '--help',          '-h',    GetoptLong::NO_ARGUMENT ]
   )

   opts.each do |opt, arg|
      case opt
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
if environment.empty? 
   STDERR.puts "You either didn't pass -e, or failed to pass an environment"
   exit -1
end

# Fetch attached EBS volumes; based on environment
all_volumes = @ec2.volumes
attachments = []
all_volumes.each do |vol| 
   attachments << vol.attachments.select { |att| att.instance.tags["environment"] == environment }
end

# strip out vols not attached to anything, then flatten the array.
attachments.delete_if { |item| item.empty? }
attachments.flatten!
volumes = attachments.map { |att| att.volume }

# Create a snapshot for each volume, tagging with Name == instance.tags["Name"]
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

# Clean up snapshots > 1 month old
threshold = Time.now - (60 * 60 * 24 * 30)

AWS.memoize do
   snapshots = @ec2.snapshots.with_owner(:self)
   snapshots.map do |snap|
      if snap.start_time < threshold and if snap.tags["autodelete"] == "true"
         p "Deleting #{snap}"
         snap.delete
      end
   end
end

#vim: set expandtab ts=3 sw=3:
