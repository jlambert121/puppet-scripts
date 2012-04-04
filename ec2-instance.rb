#!/usr/bin/env ruby
# == Synopsis
# This is a threaded program for starting up one to N VMs in EC2.
#
# == Usage
#
# --autocontrol (-a)
#   Set the autocontrol tag to true/false, which is used by the envctl script
#   to determine whether or not it is appropriate to start/stop a node when
#   doing whole environment stop/starts.
#
# --help (-h)
#   Show this help
#
# --imageid (-m)
#   Set AMI ID to use. Empty by default, meaning it's a required argument.
#
# --instancetype (-i)
#   Set max number of threads starting up VMs. Defaults to m1.large.
#
# --ppthreads (-T)
#   Set max number of threads when running Puppet. Defaults to 2.
#
# --puppetize (-p)
#   Whether or not to do Puppet operations of genkey.sh and sendkey.sh. Note
#   that genkey will run sequentially, because it has to. Sendkey however will
#   run in parallel. Defaults to false. This is a boolean so this option takes
#   no argument. Simply pass -p and it should work.
#
# --region (-r)
#   Set EC2 region such as us-east-1. Defaults to us-east-1.
#
# --securitygroup (-g)
#   Set Security Group. Required argument.
#
# --startthreads (-t)
#   Set max number of threads starting up VMs. Defaults to 2.
#
# --volumesize (-v)
#   Set volume size in gigabytes. Defaults to 8.
#
# == Notes
#
# * Node Names
# After all the -arguments, you can list N nodes. See examples below. This
# hostname setting is done via rc.local on the boxes selecting from the
# AWS instance user-data available via curl/wget to some virtual LAN address.
#
# * Thread Control
# The threads variables like --ppthreads don't currently do anything. It was
# a little much to complete in the time the script was initially needed. Will
# be fixed RSN. The goal is to keep a queue of threads running at no more than
# a maximum of the numbers given, but hopefully as close to this number
# as possible for maximum efficiency.
#
# * Terminal Reset Problem
# The threading of the sendkey script screws the terminal you're in somehow,
# maybe because of ssh -t. No time to debug yet and that section or script
# itself will likely be re-written using Net-SSH. So, you need to reset your
# terminal simply by running 'reset' after this script completes. This is the
# worst part of the code not just because of this but because I think it is
# the only reason this script must be run while your current working directory
# is ~/working/git/puppet/scripts.
#
# * Environments and Security Groups
# The staging environment matches up with the staging security group which is
# set to pass everything, with iptables on the boxes themselves. This will
# eventually work the same in prod. Unfortunately we cannot rename bm-ops-2
# to 'production'. It's just not possible in AWS. We may in the future create
# a production security group.
#
# * All the snoozing?
# The AWS API seems really sensitive to threads, therefore you'll see some
# rather excessive sleep calls, in one case 90 seconds. Yes I know this is
# bad, but it was an easy fix.
#
# * Randomizing Region Selection
# By default us-east-1 is used. If we ever get to the point of spinning up
# a bunch of instances and need real diversity for the purpose of resiliency
# to cloud failures, I will add something in the Thread.new block that calls
# run-instance to pick a random region, and keep this as even as possible.
#
# == Examples
#
# Spin up 3 nodes named acs00[1-3]-staging.thesilentpenguin.com, in staging
# security group (which will cause it to be tagged in staging environment
# as well) using our 32-bit AMI:
#
#     ./ec2-instance.rb -p --imageid ami-f587569c --securitygroup staging --instancetype c1.medium acs001-staging.thesilentpenguin.com acs002-staging.thesilentpenguin.com acs003-staging.thesilentpenguin.com
#
# Spin up 5 nodes named a[1-5] with default of m1.large using our 64 bit
# AMI and the bm-ops-2 security group, which will tag it as being in the
# production environment, and 16GB root disk:
#
#     ./ec2-instance.rb -p --imageid ami-f369bf9a --securitygroup bm-ops-ec2 --volumesize 16 a1 a2 a3
#
# Spin up 1 64-bit node named s1 with default everything except required args:
#
#     ./ec2-instance.rb -p --imageid ami-f369bf9a --securitygroup staging s1
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

# Show usage if no args are passed.
if ARGV.size == 0
   RDoc::usage
end

# Argument Defaults
autocontrol = "true"
environmenttag = ""
imageid = ""
instancetype = "m1.large"
ppthreads = 2
puppetize = false
region = "us-east-1"
securitygroup = ""
startthreads = 2
volumesize = 8

# Parse Options (1.8 style)
begin
   opts = GetoptLong.new(
      [ '--autocontrol',   '-a',    GetoptLong::REQUIRED_ARGUMENT ],
      [ '--help',          '-h',    GetoptLong::NO_ARGUMENT       ],
      [ '--imageid',       '-m',    GetoptLong::REQUIRED_ARGUMENT ],
      [ '--instancetype',  '-i',    GetoptLong::REQUIRED_ARGUMENT ],
      [ '--ppthreads',     '-T',    GetoptLong::REQUIRED_ARGUMENT ],
      [ '--puppetize',     '-p',    GetoptLong::NO_ARGUMENT       ],
      [ '--region',        '-r',    GetoptLong::REQUIRED_ARGUMENT ],
      [ '--securitygroup', '-g',    GetoptLong::REQUIRED_ARGUMENT ],
      [ '--startthreads',  '-t',    GetoptLong::REQUIRED_ARGUMENT ],
      [ '--volumesize',    '-v',    GetoptLong::REQUIRED_ARGUMENT ]
   )

   opts.each do |opt, arg|
      case opt
         when '--autocontrol'
            autocontrol = arg
         when '--help'
            RDoc::usage
         when '--imageid'
            imageid = arg
         when '--instancetype'
            instancetype = arg
         when '--ppthreads'
            begin
               ppthreads = arg.to_i
            rescue
               exit puts "You must pass an integer to --ppthreads (-T)"
            end
         when '--puppetize'
            puppetize = true
         when '--region'
            region = arg
         when '--securitygroup'
            securitygroup = arg

            # Default will never be hit here because securitygroup is a
            # required argument. Here for completeness really.
            case securitygroup
               when 'bm-ops-ec2'
                  environmenttag = "production"
               when 'staging'
                  environmenttag = "staging"
               else
                  environmenttag = "production"
            end
         when '--startthreads'
            begin
               startthreads = arg.to_i
            rescue
               exit puts "You must pass an integer to --startthreads (-t)"
            end
         when '--volumesize'
            begin
               volumesize = arg.to_i
            rescue
               exit puts "You must pass an integer to --volumesize (-v)"
            end
      end
   end
rescue => e
   puts "Error #{$!}: #{e}"
   RDoc::usage
end

if imageid.empty?
   STDERR.puts "You didn't pass --imageid (-i) to this program!"
   exit ENOIMAGEID
end

if securitygroup.empty?
   STDERR.puts "You didn't pass --securitygroup (-g) to this program!"
   exit ENOSECGROUP
end

if ARGV.size == 0
   STDERR.puts "You haven't actually put any server names to set up!"
   exit ENOHOSTS
end

ec2 = AWS::EC2.new

# Ensure specified region exists
region = ec2.regions[region]
unless region.exists?
   puts "Requested region '#{region.name}' does not exist. Valid regions:"
   puts "  " + ec2.regions.map(&:name).join("\n  ")
   exit EREGIONNOTFOUND
end

ec2 = region
image = AWS.memoize do
   our_images = ec2.images.with_owner("self").filter("image-id", imageid)
   our_images.to_a.last
end

# Set up security group
group = ec2.security_groups[securitygroup]

# Set up some arrays for the upcoming actual work
original_argvsize = ARGV.size
failed_instances = [ ]
running_instances = [ ]
threads = [ ]

# Launch instances, N simultaneously. Pop each one off ARGV to build.
puts "Launching #{ARGV.size} nodes..."
until ARGV.size == 0 or threads.size == original_argvsize do
   sleep 3
   threads << Thread.new {
      Thread.current[:iname] = ARGV.shift

      instance = image.run_instance(
                  :block_device_mappings  => {
                     "/dev/sda1" => {
                        :volume_size            => volumesize,
                        :delete_on_termination  => false
                     },
                  },
                  :instance_type    => instancetype,
                  :security_groups  => securitygroup,
                  :user_data        => Thread.current[:iname]
                 )

      # Do a retarded sleep just in case Mr. Magoo (AWS's given name) has
      # not caught up our blazing fast instantiation code. Then tag it with
      # a Name tag so it's easy to view in the web interface before adding
      # it to the array of failed_instances vs running_instances.
      begin
         sleep 5 until instance.status != :pending
      rescue
         puts "#{instance.user_data} still pending, sleeping 5..."
         retry
      end

      instance.tag(key = "Name", options = { :value => instance.user_data })
      puts "Launched #{instance.user_data},#{instance.id},#{instance.status}"

      # Also tag node with environment because querying the API for members of
      # a security group is weak sauce, and environment is just a good thing
      # to be able to query for regardless.
      instance.tag(key = "environment", options = { :value => environmenttag })

      # Set autocontrol tag which is used by envctl script to tell whether or
      # not a given node should be stopped.
      instance.tag(key = "autocontrol" options = { :value => autocontrol })

      running_instances << instance unless instance.status != :running

      if instance.status != :running
         failed_instances << instance
      end
   }
end

threads.each { |t| t.join }

if failed_instances.size > 0
   STDERR.puts "The following instances failed to go to a running state:"
   puts "  " + failed_instances.map(&[:user_data]).join("\n  ")
end

sleep 15
puts "The following instances are running:"
running_instances.each do |i|
   puts "#{i.user_data},#{i.ip_address}"
end

if puppetize == true
   puts "Puppetizing nodes..."

   # Add new nodes to local /etc/hosts
   File.open("/etc/hosts", "a") do |hostsfile|
      running_instances.each do |i|
         hostsfile.puts "#{i.ip_address} #{i.user_data}"
      end
   end

   # Generate keys, can't be threaded, sequential operation
   `./genkey.sh #{running_instances.collect(&:user_data).join(" ")}`

   # Send keys which can be threaded but will bork your terminal. Just run
   # reset after and stop complaining.
   ppthreadarray = [ ]
   running_instances.size.times do
      running_instances.each do |i|
         ppthreadarray << Thread.new {
            sleep 15

            if volumesize > 8
               `ssh #{i.user_data} 'sudo resize2fs -f /dev/sda1'`
            end

            `./sendkey.sh new #{i.user_data}`
         }
      end
   end

   ppthreadarray.each { |t| t.join }
end

#vim: set expandtab ts=3 sw=3:
