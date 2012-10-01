#!/usr/bin/env ruby
# == Synopsis
#  This is a program which can start or stop an environment in EC2, given that
#  you have an environment => environment_name tag set up in ec2.
#
# == Usage
#
# --action (-a)
#  Start or stop. This is required and script will not work if you do not
#  pass an action.
#
# --batch (-b)
#  This will suppress any confirmation messages.
#
# --env (-e)
#  Select which environment you want to perform this action on. Script will
#  warn if you specify an environment other than staging or acceptance. This
#  is a required argument as well.
#
# --help (-h)
#  Show this help
#
# == Notes
#
# None thus far.
#
# == Examples
#
# Start staging env:
#  ./ec2-envctl.rb -e staging -a start
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

require "#{File.dirname(__FILE__)}/aws-config"
require 'getoptlong'
require 'rdoc/usage'
require 'net/http'
require 'net/ssh'
require 'resolv'
require 'rubygems'

# Show usage if no args are passed.
if ARGV.size == 0
   RDoc::usage
end

# Argument Defaults
action = nil
batchmode = false
env = nil


# Parse Options (1.8 style)
begin
   opts = GetoptLong.new(
      [ '--action',        '-a',    GetoptLong::REQUIRED_ARGUMENT ],
      [ '--batch',         '-b',    GetoptLong::NO_ARGUMENT       ],
      [ '--env',           '-e',    GetoptLong::REQUIRED_ARGUMENT ],
      [ '--help',          '-h',    GetoptLong::NO_ARGUMENT       ]
   )

   opts.each do |opt, arg|
      case opt
         when '--action'
            action = arg
         when '--batch'
            batchmode = true
         when '--env'
            env = arg
         when '--help'
            RDoc::usage
      end
   end
rescue => e
   puts "Error #{$!}: #{e}"
   RDoc::usage
end

if action.nil?
   STDERR.puts "You didn't pass --action (-a) to this program!"
   RDoc::usage
end

if action != "start" and action != "stop" and action != "reboot"
   STDERR.puts "Action must be 'start', 'stop', or 'reboot'."
   RDoc::usage
end

if env.nil?
   STDERR.puts "You didn't pass --env (-e) to this program!"
   RDoc::usage
end

ec2 = AWS::EC2.new
nodes = ec2.instances.tagged("environment").tagged_values(env)
nodes = nodes.tagged("autocontrol").tagged_values("true")

# If this happens, likely invalid env passed to --env (-e)
if nodes.count == 0
   STDERR.puts "No nodes found in #{env} environment."
   exit ENONODES
end

# Compile list of node names
node_names = nodes.map { |node| node.user_data }

# Set up run stages
runstages = [ ]
runstages << { }
runstages << { }
runstages << { }

if action == "start" or action == "reboot"
   runstages[0][:regex] = /^(\w+|)db\d\d\d/
   runstages[1][:regex] = /^((?!^((\w+|)db\d\d\d|lb\d\d\d)).)*$/
   runstages[2][:regex] = /^lb\d\d\d/
elsif action == "stop"
   runstages[0][:regex] = /^lb\d\d\d/
   runstages[1][:regex] = /^((?!^((\w+|)db\d\d\d|lb\d\d\d)).)*$/
   runstages[2][:regex] = /^(\w+|)db\d\d\d/
end

# Build list of nodes in each stage.
runstages.each do |stage|
   stage[:nodes] = []

   nodes.each do |node|
      stage[:nodes] << node if node.user_data =~ stage[:regex]
   end
end

if batchmode == false
   print "Are you sure you want to #{action} all auto-controlled nodes in the #{env} environment? [y/N] "
   response = gets.chomp

   if response.downcase != "y"
      puts "Exiting based on user response..."
      exit 0
   end
end

puts "#{action.capitalize}ing all #{node_names.count} nodes in #{env} environment..."

puts "---------------------------------------------------------------------"
runstages.each_with_index do |stage,index|
   puts "Stage #{index}\n"

   stage[:nodes].each do |node|
      if action == "stop" and [:terminated, :stopped].include? node.status
         puts "#{node.user_data} is already in state #{node.status}"
         next
      end

      if action == "start" and [:running, :pending, :terminated].include? node.status
         puts "#{node.user_data} is already in state #{node.status}"
         next
      end

      print "#{action.capitalize}ing #{node.user_data}... "

      begin
         node.send action.to_sym

         if action == "start"
            resolver ||= Resolv::DNS.new(
               :nameserver => ['8.8.8.8','8.8.4.4'],
               :ndots => 1
            )

            timeout = 300
            waited = 0

            until node.status == :running or waited == timeout
               sleep 1
               waited += 1
            end

            node.associate_elastic_ip resolver.getaddress(node.user_data)

            if waited == timeout
               throw "Timed out #{action}ing node #{node.user_data}"
            end
         end

         puts "SUCCESS"
      rescue => e
         STDERR.puts "FAILURE: #{$!}: #{e}"
      end
   end

   puts "---------------------------------------------------------------------"
end

#vim: set expandtab ts=3 sw=3:
