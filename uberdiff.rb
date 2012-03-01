#!/usr/bin/env ruby
# This is a script that takes a revision or revision range from a super-
# project, and spits out all the files under submodules that have changed.
# Note that this will not output removed files.

rev = ARGV[0]
submodules = [ ]

if Dir.pwd.split("/")[-1] != "puppet"
   STDERR.puts "You must run this script from the root of the super-project."
   exit -1
end

`git diff #{rev} --submodule='log' | egrep '^Submodule (staging|production)'`.each_line do |submodule|
   if submodule.split(" ")[2].gsub(/:$/, "") == "contains"
      next
   end

   submodules << {
      :modulename => submodule.split(" ")[1],
      :revrange   => submodule.split(" ")[2].gsub(/:$/, ""),
      :changes    => [ ]
   }
end

submodules.each do |submodule|
   submodule[:changes] = `git submodule --quiet foreach 'if [ $path == "#{submodule[:modulename]}" ]; then git diff --diff-filter=ACM --name-only #{submodule[:revrange]}; fi'`.split("\n")
   submodule[:changes].map! { |change| submodule[:modulename] + File::SEPARATOR + change }
end

submodules.each do |submodule|
   puts submodule[:changes]
end

#vim: set expandtab ts=3 sw=3:
