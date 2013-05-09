#!/usr/bin/env ruby
# == Synopsis
# This is a script that takes in N nodes as arguments, snapshots their root
# volume, and ships it over to the west coast.
#
# == Usage
#
# Just pass nodes as arguments.
#
# == Notes
#
# Sometimes overcooks the pizza.
#
# == Examples
#
#     ./ec2-copysnaptowest.rb broker001.somesite.com broker002.somesite.com
#     ./ec2-copysnaptowest.rb vol-3248abde
#
# == Authors
# Joe McDonagh <jmcdonagh@thesilentpenguin.com>
#
# == Copyright
# 2013 The Silent Penguin LLC
#
# == License
# Licensed under the BSD license
#

require "#{File.dirname(__FILE__)}/aws-config"
require 'rdoc/usage'

# This will be used to keep track of how many errors we have, and it will be
# used as the exit code.
errcount = 0

# Show usage if no args are passed.
if ARGV.size == 0
   RDoc::usage
end

# Instantiate ec2 obj and find node specified.
ec2_main = AWS::EC2.new
ec2_east = ec2_main.regions["us-east-1"]
ec2_west = ec2_main.regions["us-west-1"]

ARGV.each do |input|
   unless input =~ /^vol-[a-f|A-F|1-9]{8}$/
      hostname = input
      instances = ec2_east.instances.select { |i| i.tags["Name"] == hostname }

      if instances.empty?
         STDERR.puts "The hostname #{hostname} matched no nodes, skipping!"
         errcount += 1
         next
      end

      if instances.size > 1
         STDERR.puts "The hostname #{hostname} matched multiple nodes, skipping!"
         errcount += 1
         next
      end
   
      instance = instances.first
   
      # Move to next host if root not ebs
      if instance.root_device_type != :ebs
         STDERR.puts "#{hostname} does not have an EBS volume for a root!"
         errcount += 1
         next
      end
   
      rootvol = instance.block_device_mappings[instance.root_device_name].volume
      volume = rootvol
   else
      volume = ec2_east.volumes[input]
   end

   puts "Snapshotting #{volume.id}..."
   volume_snapshot = volume.create_snapshot("snapcopy_#{input}_#{Time.now.strftime('%Y%m%d')}")
   # Show progress bar for volume snapshot
   until [:completed, :error].include? volume_snapshot.status
      sleep 5
      printf "\r|"
      (volume_snapshot.progress.to_i / 8).times {|i| printf "=" }
      printf "> "
      printf "%s%%", volume_snapshot.progress
      STDOUT.flush
   end
   printf "\n"
   
   if volume_snapshot.status == :error
      STDERR.puts "Error creating snapshot of #{input}!"
      errcount += 1
      next
   end

   puts "Copying #{volume.id} to west coast..."
   copysnapshot_response = ec2_west.client.copy_snapshot(
      :source_region => "us-east-1",
      :source_snapshot_id => volume_snapshot.id,
      :description => "snapcopy_#{input}_#{Time.now.strftime('%Y%m%d')}")

   westcoast_snapshot_id = copysnapshot_response[:snapshot_id]
   westcoast_snapcopy = ec2_west.snapshots[westcoast_snapshot_id]

   # Show progress bar for west coast copy of snapshot
   until [:completed, :error].include? westcoast_snapcopy.status
      sleep 5
      printf "\r|"
      (westcoast_snapcopy.progress.to_i / 8).times {|i| printf "=" }
      printf "> "
      printf "%s%%", westcoast_snapcopy.progress
      STDOUT.flush
   end
   printf "\n"
   
   if westcoast_snapcopy.status == :error
      STDERR.puts "Error creating snapcopy on west coast for #{input}!"
      errcount += 1
      next
   end
end

exit errcount
#vim: set expandtab ts=3 sw=3:
