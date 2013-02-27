#!/usr/bin/env ruby
#
# Hack script to throw together a new ticket.
#

require File.expand_path("~/working/git/puppet/priv/lighthouse-config")
require 'pry'

# Systems group user IDs
systems_team = {
   :byoung => {
      :name => "Bill Young",
      :id   => 125039
   },
   :jmcdonagh => {
      :name => "Joe McDonagh",
      :id   => 174664
   },
   :egoodman => {
      :name => "Eben Goodman",
      :id   => 174736
   }
}

assignee = ""
ticket_title = []
ticket_overview = []
ticket_solution = []
ticket_testing = []
ticket_body = ""
ticket_tags = []

print "Title (Hit Enter when done): "
ticket_title = gets.chomp

print "Overview (hit enter, ctrl D when done): "
ticket_overview << STDIN.read { |input| input }
print "Solution (hit enter, ctrl D when done): "
ticket_solution << STDIN.read { |input| input }
print "Testing (hit enter, ctrl D when done): "
ticket_testing << STDIN.read { |input| input }

loop do
   print "Assignee (hit enter when done): "
   assignee = gets.chomp

   if !systems_team.keys.include? assignee.to_sym
      puts "Error, user not member of systems team, retry"
   else
      break
   end
end

print "Tags (Space-Separated, enter when done): "
ticket_tags = gets.chomp.split(" ")

ticket_body = "### Overview ###\n\n"
ticket_body += ticket_overview.join("\n") + "\n"
ticket_body += "### Solution ###\n\n"
ticket_body += ticket_solution.join("\n") + "\n"
ticket_body += "### Testing ###\n\n"
ticket_body += ticket_testing.join("\n") + "\n"

l = Lighthouse::Ticket.create(
   :project_id       => 41389,
   :title            => ticket_title,
   :state            => "open",
   :body             => ticket_body,
   :assigned_user_id => systems_team[assignee.to_sym][:id]
)

# This can't be done during creation due to an API bug
l.tags = ticket_tags
l.save

puts "Ticket ##{l.id} created:"
puts l.url
