#!/usr/bin/env ruby
# == Synopsis
# This is a program that automates EBS Snapshots in AWS.
#
# == Usage
#
# --environment (-e)
#   Specify the environment to snapshot. This will snapshot all volumes that
#   are currently attached to nodes in the given environment(s). If a volume
#   is unattached at the time you run this script, you are out of luck because
#   environment is gleaned from the attached instance's environment tag.
#
# --force (-f)
#   What force means in this case, is that even if the volume
#   has autocontrol set to false, it will still snapshot the
#   volume.
#
# --host (-H)
#   Take snapshot of all volumes attached to host(s).
#
# --region (-r)
#   Which region to work in, eg us-east-1 or us-west-1.
#
# --volume (-V)
#   Volume ID(s) to snapshot, useful if you want to snapshot only one specific
#   volume or set of volumes without also snapshotting root vols etc.
#
# --help (-h)
#   Show this help
#
# == Notes
#  This script can take in N arguments by looping through ARGV. What that
#  means is that if you need to take a snapshot of all three environments,
#  all you do is:
#
#  ./ec2-snapshot.rb -e testing staging production
#
#  This works for both hosts and volumes as well.
#
# == Authors
# Bill Young <byoung2@berklee.edu>
# Joe McDonagh <jmcdonagh@thesilentpenguin.com> 
#
# == Copyright
# 2012 The Silent Penguin LLC
#
# == License
# Licensed under GPLv2
#

require "#{File.dirname(__FILE__)}/aws-config"
require 'rdoc/usage'

# Show usage if no args are passed.
if ARGV.size == 0
   RDoc::usage
end

# Argument defaults
force       = false
mode        = ""
region      = "us-east-1"

def get_volumes(mode, ec2, force)
   volumes = []

   case mode
      when 'environment'
         ARGV.each do |environment|
            all_volumes = ec2.volumes
            attachments = []
   
            all_volumes.each do |vol| 
               attachments << vol.attachments.select { |att| att.instance.tags["environment"] == environment }
            end
         
            # Strip out vols not attached to anything, then flatten the array.
            attachments.delete_if { |item| item.empty? }
            attachments.flatten!
         
            # Get volume array from attachments
            volumes << attachments.map { |att| att.volume }
            volumes.flatten!
         end
      when 'host'
         ARGV.each do |host|
            node = ec2.instances.select do |instance|
               instance.tags["Name"] == host
            end

            if node.empty?
               STDERR.puts "Skipping host #{host} because your identifier matched no nodes!"
               next
            end

            if node.count > 1
               STDERR.puts "Skipping host #{host} because the name matched multiple instances!"
               next
            end

            node = node.first

            if node.attachments.count == 0
               STDERR.puts "Skipping host #{host} as it appears to have no EBS volumes attached!"
               next
            end 

            node.attachments.each_key do |mountpoint|
               volumes << node.attachments[mountpoint].volume
            end
         end
      when 'volume'
         ARGV.each do |volume_id|
            volumes << ec2.volumes[volume_id] unless ec2.volumes[volume_id].tags["autocontrol"] == "false"
         end
   end

   if force != true
      volumes.delete_if { |vol| vol.tags["autocontrol"] == "false" }
   end

   volumes
end


def create_snapshots(volumes)
   unless volumes.is_a? Array
      fail "Must pass an array to create_snapshots method"
   end

   volumes.each do |vol|
      if vol.attachments.count == 0
         hostname = "UNATTACHED_VOLUME"
      else
         hostname = vol.attachments.first.instance.tags["Name"]
      end

      printf "Creating snapshot of host %s volume %s\n", hostname, vol.id 
      STDOUT.flush

      snap = vol.create_snapshot("#{hostname} - #{vol.id} - #{Time.now.to_s}")
      snap.tags["Name"] = hostname
      snap.tags["autodelete"] = "true"

      until [:completed, :error].include? snap.status
         printf "\r"
         printf "%s%%", snap.progress
         STDOUT.flush
         sleep 5
      end
 
      if snap.status == :completed
         printf " SUCCESS!\n"
      else
         printf " ERROR!\n"
      end
    end
end

# Parse Options
begin
   opts = GetoptLong.new(
      [ '--environment',   '-e',    GetoptLong::NO_ARGUMENT],
      [ '--force',         '-f',    GetoptLong::NO_ARGUMENT ],
      [ '--host',          '-H',    GetoptLong::NO_ARGUMENT ],
      [ '--region',        '-r',    GetoptLong::REQUIRED_ARGUMENT ],
      [ '--volume',        '-V',    GetoptLong::NO_ARGUMENT ],
      [ '--help',          '-h',    GetoptLong::NO_ARGUMENT ]
   )

   opts.each do |opt, arg|
      case opt
         when '--environment'
            mode = "environment"
         when '--force'
            force = true
         when '--host'
            mode = "host"
         when '--volume'
            mode = "volume"
         when '--help'
            RDoc::usage
      end
   end
rescue => e
   STDERR.puts "#{e}"
   RDoc::usage
end
         
unless %w{environment host volume}.include? mode
   fail "You must pass either environment (-e), host (-H) or volume (-V) to the script!"
end

begin
   ec2 = AWS::EC2.new
   ec2 = ec2.regions[region]
rescue => e
   fail "#{e}"
end

volumes = AWS.memoize { get_volumes(mode, ec2, force) }
create_snapshots(volumes)

#vim: set expandtab ts=3 sw=3:
