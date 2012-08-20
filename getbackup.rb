#!/usr/bin/env ruby
# == Synopsis
# This is a program that retrieves backups from s3.
#
# == Usage
#
# --bucket (-b)
#   Specify the bucket. Defaults to bm-backup.
#
# --host (-H)
#   List backups for a given host
#
# --help (-h)
#   Show this help
#
# == Notes
# You can specify a range at the index prompt, with number-number, like:
# 
# 0-3
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
require 'rubygems'
require 'aws-config'
require 'aws-sdk'
require 'getoptlong'
require 'rdoc/usage'
require 'sys/filesystem'

# Show usage if no args are passed.
if ARGV.size == 0
   RDoc::usage
end

bucketname = ""
downloads = []
host = ""

# Parse Options (1.8 style)
begin
   opts = GetoptLong.new(
      [ '--bucket',        '-b',   GetoptLong::REQUIRED_ARGUMENT  ],
      [ '--host',          '-H',   GetoptLong::REQUIRED_ARGUMENT  ],
      [ '--help',          '-h',   GetoptLong::NO_ARGUMENT        ]
   )

   opts.each do |opt, arg|
      case opt
         when '--bucket'
            bucketname = arg
         when '--host'
            host = arg
         when '--help'
            RDoc::usage
      end
   end
rescue
   puts "Error: #{$!}"
   RDoc::usage
end

if host.nil? or host.empty?
   STDERR.print "Error, you didn't specify the host!"
end

if bucketname.nil? or bucketname.empty?
   bucketname = "bm-backup"
end

begin
   s3 = AWS::S3.new
rescue => err
   abort "Problem loading S3 Error ##{$!}: #{err}"
end

begin
   bucket = s3.buckets[bucketname]
   objects = bucket.objects.select { |obj| obj.key =~ /^#{Regexp.escape(host)}/ }
rescue => err
   abort "Problem accessing the bucket #{bucketname}, #{$!}: #{err}"
end

if objects.size == 0 or objects.nil?
   printf "No backups found for host %s in bucket %s!\n", host, bucketname
   exit 0
end

printf "The following is a list backups under hostname %s in bucket %s\n\n", host, bucketname
printf "%5s %15s %s\n", "INDEX", "BYTES", "FILEKEY"
printf "--------------------------------------------------------------\n"
objects.each_with_index do |obj,index|
   printf "%5s %15s %s\n", index.to_s, obj.content_length, obj.key
end
printf "\nEnter the item number you wish to download (defaults to last): "
answer = gets

if answer.nil?
   answer = objects.size - 1
end

if answer =~ /(\d+)-(\d+)/
   range_low = $1.to_i
   range_high = $2.to_i

   for index in range_low..range_high
      downloads << objects[index]
   end
else
   downloads << objects[answer.to_i]
end

downloads.each do |download|
   begin
      fsstat = Sys::Filesystem.stat(".")
      bytes_available = fsstat.block_size * fsstat.blocks_available

      if download.content_length > bytes_available
         throw "Not enough room to download #{download.key.split("/").last}!"
      end

      Dir.mkdir download.key.split("/")[-2] unless File.directory? download.key.split("/")[-2]
      printf "Downloading %s... ", download.key
      STDOUT.flush
      File.open(download.key.split("/")[-2..-1].join(File::SEPARATOR), "w") do |f|
         f.write(download.read)
      end

      printf "SUCCESS!\n"
   rescue => err
      STDERR.puts "Error: #{$!} #{err}"
   end
end

Kernel.exit 0

#vim: set expandtab ts=3 sw=3:
