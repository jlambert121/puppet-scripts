#!/usr/bin/env ruby
# == Synopsis
# This is a small script that will show differences in our two sources of
# truth; mcollective and puppet stored config db. It will simply output a
# list of nodes that are in MCO but not in Puppet's DB, then it will be
# the other way around.
#
# == Usage
#
# --help (-h)
#   Show this help
#
# --version (-v)
#   Show version
#
# == Notes
# This program sometimes overcooks the pizza.
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

require 'getoptlong'
require 'puppet/rails'
require 'mcollective'

include MCollective::RPC

config = '/etc/puppet/puppet.conf'

opts = GetoptLong.new(
    [ "--config",      "-c",   GetoptLong::REQUIRED_ARGUMENT ],
    [ "--help",        "-h",   GetoptLong::NO_ARGUMENT ],
    [ "--usage",       "-u",   GetoptLong::NO_ARGUMENT ],
    [ "--version",     "-v",   GetoptLong::NO_ARGUMENT ]
)

begin
  opts.each do |opt, arg|
    case opt
      when "--help"
         RDoc::usage
      when "--version"
         puts "#{Puppet.version}"
         exit
      end
  end
rescue GetoptLong::InvalidOption => detail
  $stderr.puts "Try '#{$0} --help'"
  exit(1)
end

# Parse Puppet config
Puppet[:config] = config
Puppet.parse_config
pm_conf = Puppet.settings.instance_variable_get(:@values)[:master]

# Instantiate mc client
mc = rpcclient("discovery")

# Get list of nodes, sort
mc_nodelist = mc.discover
mc_nodelist.sort!

adapter = pm_conf[:dbadapter]
args = {:adapter => adapter, :log_level => pm_conf[:rails_loglevel]}

case adapter
  when "sqlite3"
    args[:dbfile] = pm_conf[:dblocation]
  when "mysql", "postgresql"
    args[:host]     = pm_conf[:dbserver] unless pm_conf[:dbserver].to_s.empty?
    args[:username] = pm_conf[:dbuser] unless pm_conf[:dbuser].to_s.empty?
    args[:password] = pm_conf[:dbpassword] unless pm_conf[:dbpassword].to_s.empty?
    args[:database] = pm_conf[:dbname] unless pm_conf[:dbname].to_s.empty?
    args[:port]     = pm_conf[:dbport] unless pm_conf[:dbport].to_s.empty?
    socket          = pm_conf[:dbsocket]
    args[:socket]   = socket unless socket.to_s.empty?
  else
    raise ArgumentError, "Invalid db adapter #{adapter}"
end

args[:database] = "puppet" unless not args[:database].to_s.empty?

ActiveRecord::Base.establish_connection(args)

puppet_nodelist = Puppet::Rails::Host.find_all
puppet_nodelist.sort!

printf "The following nodes are in mcollective, but not puppet:\n"
(mc_nodes - puppet_nodes).each { |node| printf "%s\n", node }

printf "The following nodes are in puppet, but not mcollective:\n"
(puppet_nodes - mc_nodes).each { |node| printf "%s\n", node }

exit 0
