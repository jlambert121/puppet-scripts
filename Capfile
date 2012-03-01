# This is a simple Capfile that demonstrates using the store config db to
# enumerate hosts, which you can then put in specific roles, and run tasks
# against them.

#=============================================================================
# If you have Add-on libraries, load them here
#=============================================================================

#require 'customlibrary'  

#=============================================================================
# Options
#=============================================================================

set :ssh_options, { :forward_agent => true }
set :use_sudo, "true"

#---------------------------BEGINNING OF ROLES-------------------------------#
#=============================================================================
# Static Roles
#
# The only role we really need in here is the puppet_db, since node
# information can be gathered from the stored config databases.
#=============================================================================

role :puppet_db,
   "puppet"

#=============================================================================
# Dynamic Roles
#
# These are defined empty because they are filled by the enum_hosts task.
#=============================================================================

# Role for puppet masters
role "puppet_masters" do end

#------------------------------END OF ROLES----------------------------------#

#---------------------------BEGINNING OF TASKS-------------------------------#
#=============================================================================
# Namespace: global
#
# Purpose: Tasks for host enumeration and populating dynamic roles. Purposes
# for each task are in their descriptions. This should be in a namespace but
# roles can't be defined inside a namespace. This can be extremely useful if
# mcollective is down or not yet deployed.
#=============================================================================

task :enum_hosts, :roles => [:puppet_db] do
   desc "Enumerate hosts and fill appropriate roles from puppet DB"

   counter = 0
   role_number = 0

   logger.info "Hosts:"

   # This block splits up into roles determinable by hostname.
   run 'sudo mysql -s -D puppet -e "select name from hosts;" | sed 1d', :pty => true do |ch, stream, out|
      next if out.chomp == ''
      logger.info out.sub(/\//,' ') 
      out.split("\r\n").each do |host|
        if host.empty?
           next
        end

        # Add box to role all_hosts
        role("all_hosts", host)

        # Puppet masters
        if host =~ /^puppet\..*$/ role("puppet_masters", host) end

        # Environment roles for all hosts
        if host =~ /-staging\..*$/
           role("all_staging", host)
        else
           role("all_production", host)
        end

        # Split nodes into chunks of 10, since ssh agent sucks. Will create
        # Roles like role1, role2, role3, etc.
        role(("hosts" + role_number.to_s), host)

        counter = counter + 1
        if counter > 10
           role_number = role_number + 1
           counter = 0
        end

        # Guess that nodes can be put into roles of beginning alpha string,
        # ie www001.yoursite.com should go into a role named www.
        matched_role = host.match(/^[[:alpha:]]+/).to_s
        role(matched_role, host)

        # Now put machines in domain role. If you have a flat domain, this
        # might be useless. But if you have several this can be immensely
        # helpful. I will be adding OS-roles soon too, which are in another
        # Capfile I have somewhere.
        role(host.split(".")[-2..-1].join("."), host)
      end
   end
end

#=============================================================================
# Namespace: admin
#
# Description: General administration tasks go here.
#=============================================================================

namespace :admin do
   desc "Remove /etc/sysconfig/puppet and restart puppet"
   task :chewychomp, :max_hosts => 5, :on_error => "continue"  do
      begin
         run "sudo rm -f /etc/sysconfig/puppet; sudo /etc/init.d/puppet stop; sudo /etc/init.d/puppet start"
      rescue
         true
      end
   end
end

#------------------------------END OF TASKS----------------------------------#

#-----------------------BEGINNING OF CAPFILE BODY----------------------------#

# Here we ask whether or not to populate the dynamic roles on start-up.
if Capistrano::CLI.ui.ask("Populate dynamic roles? (y/n): ") == ("Y" or "y")
   enum_hosts
end

#------------------------------END OF BODY-----------------------------------#
#vim: set expandtab ts=3 sw=3:
