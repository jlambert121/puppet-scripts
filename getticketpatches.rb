#!/usr/bin/env ruby
# == Synopsis
# This is a script to get all patches in production for a specific ticket.
#
# == Usage
#
# --ticket (-t)
#  ticket number to show patches for
#
# --help (-h)
#  Show this help
#
# == Notes
# This program sometimes overcooks the pizza.
#
# == Authors
# Joe McDonagh <jmcdonagh@berkleemusic.com>
#
# == Copyright
# 2012 Berklee Media
#
# == License
# Licensed under Berklee Media Use Only
#

require 'getoptlong'
require 'rdoc/usage'
require 'rubygems'
require 'open4'
require 'pry'

patches = ""
ticket = nil

# Show usage if no args are passed.
if ARGV.size == 0
  RDoc::usage
end

# Parse Options (1.8 style)
begin
  opts = GetoptLong.new(
    [ '--help',   '-h', GetoptLong::NO_ARGUMENT       ],
    [ '--ticket', '-t', GetoptLong::REQUIRED_ARGUMENT ]
  )

  opts.each do |opt, arg|
    case opt
      when '--help'
        RDoc::usage
      when '--ticket'
        ticket = arg
    end
  end
rescue
  puts "Error: #{$!}"
  RDoc::usage
end

if ticket.nil? or ticket.to_i == 0
  STDERR.puts "You have entered a bad ticket number!"
  exit -1
end

Open4.popen4("git submodule --quiet foreach 'if [[ $path =~ ^production.* ]]; then git log --oneline | grep #{ticket} | cut -d\" \" -f1 | xargs git show || true; fi'") do |pid, stdin, stdout, stderr|
  patches << stdout.gets until stdout.eof?
end 

if patches.empty?
  STDERR.puts "No patches listed for commits!"
  exit -42
end

patches.each_line{ |line| printf "%s", line }

#vim: set expandtab ts=2 sw=2:
