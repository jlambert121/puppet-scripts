#!/usr/bin/env ruby
# == Synopsis
# This is a program that removes old snapshots from EC2.
#
# == Usage
#
# --region (-r)
#   Which region to work in, eg us-east-1 or us-west-1.
#
# --threshold (-t)
#   Number in days that sets threshold of snapshots to remove. The default
#   is 30, meaning snapshots older than 30 days will be removed (if the
#   snapshot's tag "autodelete" is set to "true".
#
# --help (-h)
#   Show this help
#
# == Notes
#  If you want to snapshot a volume and not have it be removed by this script
#  just set don't tag it with autodelete = true.
#
# == Authors
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

# Argument defaults
region         = ""
threshold_days = 30

# Parse Options
begin
   opts = GetoptLong.new(
      [ '--region',        '-r',    GetoptLong::REQUIRED_ARGUMENT ],
      [ '--threshold',     '-t',    GetoptLong::REQUIRED_ARGUMENT ],
      [ '--help',          '-h',    GetoptLong::NO_ARGUMENT ]
   )

   opts.each do |opt, arg|
      case opt
         when '--region'
            region = arg
         when '--threshold'
            threshold_days = arg.to_i
         when '--help'
            RDoc::usage
      end
   end
rescue => e
   puts "Error #{$!}: #{e}"
   RDoc::usage
end

if region.empty?
   fail "Must at least pass a region (-r) to cleanup snapshots in!"
end

if threshold_days == 0
   fail "It appears you passed either 0 or a non-integer argument to threshold (-t)!"
end

begin
   ec2 = AWS::EC2.new
   ec2 = ec2.regions[region]
rescue => e
   fail "#{e}"
end

# Set up time object of threshold_days days ago
threshold = Time.now - (60 * 60 * 24 * threshold_days)

AWS.memoize do
   snapshots = ec2.snapshots.with_owner(:self)
   snapshots.map do |snap|
      if snap.start_time < threshold and snap.tags["autodelete"] == "true"
         p "Deleting #{snap}"
         STDOUT.flush

         begin
            snap.delete
         rescue => e
            STDERR.puts "#{e}"
            next
         end
      end
   end
end

#vim: set expandtab ts=3 sw=3:
