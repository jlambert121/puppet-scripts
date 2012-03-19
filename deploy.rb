# Configuration Variables. Please note that you must have a site.pp with the
# set of variables expected to be set by the GRUMPS setup.
set :local_checkout,          "#{ENV['HOME']}/working/git/puppet"
set :organization_name,       %x[grep '$organization_name' #{local_checkout}/production/manifests/site.pp | awk -F' ' '{ print $NF }' | tr -d '"'].chomp
set :organization_github,     %x[grep '$organization_github' #{local_checkout}/production/manifests/site.pp | awk -F' ' '{ print $NF }' | tr -d '"'].chomp
set :organization_tld,        %x[grep '$organization_tld' #{local_checkout}/production/manifests/site.pp | awk -F' ' '{ print $NF }' | tr -d '"'].chomp

set :admin_group,             %x[grep '$admin_group' #{local_checkout}/production/manifests/site.pp | awk -F' ' '{ print $NF }' | tr -d '"'].chomp
set :admin_group_gid,         %x[grep '$admin_group_gid' #{local_checkout}/production/manifests/site.pp | awk -F' ' '{ print $NF }' | tr -d '"'].chomp
set :app_user,                "puppet"
set :application,             "puppet"
set :copy_exclude,            [ ".git" ]
set :deploy_lockfile,         "/tmp/puppet_being_deployed"
set :deploy_to,               "/usr/local/puppet"
set :deploy_via,              "remote_cache"
set :git_enable_submodules,   1
set :keep_releases,           5
set :notification_email,      %x[grep '$admin_group_email' #{local_checkout}/production/manifests/site.pp | awk -F' ' '{ print $NF }' | tr -d '"'].chomp
set :repo_host,               "packages.#{organization_tld}"
set :repo_pkg_url,            "http://packages.#{organization_tld}/centos/6/x86_64/repo-6-1.noarch.rpm"
set :repository,              "ssh://git@github.com/#{organization_github}/puppet"
set :scm,                     "git"
set :storedconfig_password,   %x[grep dbpassword #{local_checkout}/puppet.conf | awk -F' ' '{ print $NF }'].chomp
set :use_sudo,                "true"
set :use_storeconfigs,        "true"

# SSH Config Variables
ssh_options[:forward_agent] = true

# Role for deployment
role :puppet_masters,
   "puppet.#{organization_tld}"

# Task to run after everything is done. This runs every time.
task :afterparty do
   run "if [ ! -d /etc/#{application} ]; then sudo -u root mkdir /etc/#{application}; fi"
   run "sudo -u root rsync --exclude='tagmail.conf' --delete -clvrP --no-o --no-g --no-p #{deploy_to}/current/ /etc/#{application}/"
   run "sudo -u root chown -R root:#{app_user} /etc/#{application}; sudo -u root find /etc/#{application} -type d -name 'lib' -prune -o -type d -exec chmod 750 {} \\; && sudo chmod -R g+r /etc/#{application}"
   run "sudo -u root find /etc/#{application} -type d -name 'lib/*' -exec chmod -R 755 {} \\;"
   run "sudo -u root chmod -R g+w #{deploy_to}/shared/cached-copy"

   # This is retarded but, this command can fail along with the other mv below
   # so we have to account for that and catch the exception. We can't set this
   # task to on_error => continue cause if rsync fails, i want a rollback.
   begin
      run "sudo test -e /etc/puppet/tagmail.conf && sudo -u root mv /etc/puppet/tagmail.conf /tmp/tagmail.conf"
   rescue
      true
   end

   run "sudo -u root /etc/init.d/apache2 restart"

   begin
      run "sudo test -e /tmp/tagmail.conf && sudo -u root mv -f /tmp/tagmail.conf /etc/puppet/tagmail.conf"
   rescue
      true
   end
end

# Generate puppet docs
task :gendocs, :on_error => :continue do
   run "sudo rm -rf /var/www/puppetdocs/staging /var/www/puppetdocs/production"
   run "sudo /usr/bin/puppet doc -a -m rdoc --outputdir /var/www/puppetdocs/staging/ --manifestdir /etc/puppet/staging/manifests --modulepath '/etc/puppet/staging/grumps-modules:/etc/puppet/staging/#{organization_name}-modules'"
   run "sudo /usr/bin/puppet doc -a -m rdoc --outputdir /var/www/puppetdocs/production/ --manifestdir /etc/puppet/production/manifests --modulepath '/etc/puppet/production/grumps-modules:/etc/puppet/production/#{organization_name}-modules'"
end

# This task won't do much to repair a broken git repo
task :fix_deploys, :on_error => :continue do
   logger.info "Make cached check out group-writeable by #{admin_group}..."
   run "sudo -u root chgrp -R #{admin_group} #{deploy_to}/shared/cached-copy"
   run "sudo -u root chmod -R g+w #{deploy_to}/shared/cached-copy"
   logger.info "Get repo to pristine state..."
   run "git checkout #{deploy_to}/shared/cached-copy"
   logger.info "Force permission fixes..."
   run "sudo -u root find #{deploy_to}/shared/cached-copy -type d -exec chmod 2770 {} \\;"
   run "sudo -u root find #{deploy_to}/shared/cached-copy -type f -exec chmod 660 {} \\;"
   logger.info "Unlocking deploys..."
   run "sudo -u root rm -f #{deploy_lockfile}"
end

task :notify do
   require 'etc'
   require 'rubygems'
   require 'action_mailer'

   ActionMailer::Base.delivery_method = :sendmail
   ActionMailer::Base.sendmail_settings = { 
      :location   => '/usr/sbin/sendmail', 
      :arguments  => '-i -t'
   }

   class NotificationMailer < ActionMailer::Base
      def deployment(application, message, notification_email, from_domain)
         mail(
            :from    => "#{Etc.getpwnam(ENV['USER']).gecos} <#{ENV['USER']}@#{from_domain}>",
            :to      => notification_email,
            :subject => "Puppet Deployment - #{Time.now.to_s}",
            :body    => message
         )
      end
   end

   message = "This is a notification of deployment of a Puppet update.\n\n"
   message << "Deployed at: #{Time.now.to_s}\n"
   message << "Revision: #{real_revision}\n\n"

   # if the revision has not changed then don't look for logs, also if #SEC
   # is in the commit message, a full diff is not displayed for security
   # reasons.
   begin
      if previous_revision != real_revision
         message << "SCM Revisions Deployed\n"
         gitlog = `#{source.local.log(latest_revision, real_revision)} -v --oneline`
         if gitlog.include? '#SEC'
            message << gitlog
         else
            message << `#{source.local.log(latest_revision, real_revision)} --submodule=log -v --patch-with-stat`
         end
      end
   rescue
      message << "SCM Revisions Deployed\n"
      message << 'Previous revision not available'
   end

   mail = NotificationMailer.deployment(application, message, notification_email, organization_tld)
   mail.deliver
end

# Task that cats out what revision is deployed
task :getrev do
   run "sudo -u root cat /etc/puppet/REVISION"
end

# Task to add a lock file and bail deploys with a message if one exists
task :lock_deploys do
   require 'etc'

   logger.info "Locking deploys..."

   if ENV.has_key?('lock_reason')
      lock_reason = ENV['lock_reason']
   else
      lock_reason = "Deployment"
   end

   data = capture("cat #{deploy_lockfile} 2>/dev/null; echo").to_s.strip

   if !data.empty?
      logger.info "\e[0;31;1mATTENTION:\e[0m #{data}"
      abort "Deploys are locked."
   end

   timestamp = Time.now.strftime("%m/%d/%Y %H:%M:%S %Z")
   lock_message = "Deploys locked by #{Etc.getpwnam(ENV['USER']).gecos} (#{ENV['USER']}) at #{timestamp} for #{lock_reason}"
   put lock_message, "#{deploy_lockfile}", :mode => 0644
end

task :unlock_deploys do
   logger.info "Unlocking deploys..."
   run "rm -f #{deploy_lockfile}"
end

# Task to run before anything is done. Generally this is once only.
task :prep, :on_error => "continue" do
   grepped_admin_group = capture("grep #{admin_group} /etc/group") rescue ""

   if grepped_admin_group.empty? or grepped_admin_group.nil?
      begin
         run "sudo -u root groupadd -g #{admin_group_gid} #{admin_group}"
      rescue
         abort "Failure adding admin_group #{admin_group}, aborting as subsequent things will fail."
      end
   else
      run "sudo -u root groupmod -g #{admin_group_gid} #{admin_group}"
   end

   run "sudo -u root usermod -a -G #{admin_group} #{ENV['USER']}"
   run "sudo -u root mkdir -p /etc/mysql /etc/puppet /usr/share/puppet/rack/public"
   run "sudo -u root mkdir -p /tmp/bootstrap_master; sudo -u root chmod 1777 /tmp/bootstrap_master"

   # Figure out if it's RH or not to know package manager
   distro_data = capture("cat /etc/redhat-release 2>/dev/null; echo").to_s.strip
   if distro_data.empty? or distro_data.nil?
      pkg_manager = "apt-get"
      git_pkgname = "git-core"
   else
      pkg_manager = "yum"
      git_pkgname = "git"
   end

   # Ensure my.cnf is in place before mysql is installed otherwise innodb
   # log files are configured all wrong. Also install get-puppet-revision
   # which the master needs to display the deployed git revision when
   # running a catalog on a client.
   upload "#{local_checkout}/bootstrap_master/tagmail.conf", "/tmp/bootstrap_master/tagmail.conf"
   upload "#{local_checkout}/bootstrap_master/my.cnf", "/tmp/bootstrap_master/my.cnf"
   upload "#{local_checkout}/bootstrap_master/config.ru", "/tmp/bootstrap_master/config.ru"
   upload "#{local_checkout}/production/grumps-modules/puppet/files/master/get-puppet-revision", "/tmp/bootstrap_master/get-puppet-revision"
   run "sudo -u root chmod 755 /tmp/bootstrap_master/get-puppet-revision"

   run "sudo mv /tmp/bootstrap_master/tagmail.conf /etc/puppet/"
   run "sudo mv /tmp/bootstrap_master/my.cnf /etc/mysql/"
   run "sudo mv /tmp/bootstrap_master/get-puppet-revision /usr/local/bin/"
   run "sudo mv /tmp/bootstrap_master/config.ru /usr/share/puppet/rack/"

   # Upload passenger config to proper http config dir, and install packages
   if pkg_manager == "apt-get"
      # Set up custom repo
      run "sudo -u root apt-get install -y --force-yes facter apache2"
      distrelease = capture("facter lsbdistrelease 2>&1").to_s.strip
      lcase_distro = capture("facter lsbdistid 2>&1").to_s.downcase.strip
      apt_uri = "http://#{repo_host}/#{lcase_distro}/#{distrelease}"
      distribution = capture("facter lsbdistcodename 2>&1").to_s.strip
      source_string = "deb #{apt_uri} #{distribution} main\n"
      run "wget -O - http://#{repo_host}/packages.pub | sudo -u root apt-key add -"
      put source_string, "/tmp/bootstrap_master/#{organization}.list", :mode => 0644
      run "sudo -u root mv -f /tmp/bootstrap_master/#{organization_name}.list /etc/apt/sources.list.d/#{organization_name}.list"
      run "sudo -u root apt-get update"
      
      upload "#{local_checkout}/bootstrap_master/puppetmaster", "/tmp/bootstrap_master/puppetmaster"
      run "sudo -u root mv /tmp/bootstrap_master/puppetmaster /etc/apache2/sites-available/"
      run "sudo -u root a2ensite puppetmaster"

      if use_storeconfigs == "true"
         # Install all the MySQL-related packages
         run "gpg --keyserver hkp://keys.gnupg.net --recv-keys 1C4CBDCDCD2EFD2A"
         run "gpg -a --export CD2EFD2A | sudo -u root apt-key add -"
         percona_string = "deb http://repo.percona.com/apt lucid main\n"
         put percona_string, "/tmp/bootstrap_master/percona.list", :mode => 0644
         run "sudo -u root mv -f /tmp/bootstrap_master/percona.list /etc/apt/sources.list.d/percona.list"
         run "sudo -u root apt-get update"
         run "sudo -u root apt-get install -y --force-yes -o Dpkg::Options::='--force-confold' percona-server-server-5.1 percona-server-client-5.1"
      end

      # Install all the puppet master packages
      run "sudo -u root apt-get install -y --force-yes libdaemons-ruby1.8 libldap-ruby1.8 libmysql-ruby librrd2-dev libsqlite3-ruby1.8 puppetmaster puppetmaster-common puppetmaster-passenger rails rdoc"
   else
      # Ensure i386 packages are ignored if on x86_64 (really should be)
      architecture = capture("uname -m") rescue ""
      if architecture == "x86_64"
         run "sudo -u root bash -c \"echo 'exclude = *.i?86' >> /etc/yum.conf\""
      end

      begin
         run "sudo -u root rpm -ivh #{repo_pkg_url}"
      rescue
         abort "Failure installing custom repo package from #{repo_pkg_url}!"
      end

      if use_storeconfigs == "true"
         # Install all the MySQL-related packages
         run "sudo -u root yum install -y Percona-Server-server-51 Percona-Server-client-51"
      end

      # Install all the puppet master packages
      run "sudo -u root yum install -y apr-devel httpd gcc-c++ httpd-devel make mod_ssl puppet-serverruby-devel ruby-mysql ruby-rdoc rubygem-actionmailer rubygem-actionpack rubygem-activerecord rubygem-activeresource rubygem-activesupport rubygem-fastthread rubygem-passenger rubygem-rack rubygem-rails rubygem-rake"

      # Capture version, in 6 need mod_passenger, in 5 need to compile
      rhel_version = capture("facter operatingsystemrelease").to_s.strip
      if rhel_version =~ /^6\.\d+/
         run "sudo -u root yum install -y mod_passenger policycoreutils-python"
      else
         run "sudo -u root yum install -y policycoreutils"
         run "sudo -u root /usr/lib/ruby/gems/1.8/gems/passenger-2.2.11/bin/passenger-install-apache2-module -a"
      end

      begin
         run "sudo -u root /usr/sbin/semanage port -a -t http_port_t -p tcp 8140"
      rescue
         logger.info "There was a problem opening port 8140 as type http_port_t for SELinux."
      end

      upload "#{local_checkout}/bootstrap_master/puppetmaster", "/tmp/bootstrap_master/puppetmaster.conf"
      run "sudo -u root mv /tmp/bootstrap_master/puppetmaster.conf /etc/httpd/conf.d/"
      run "sudo -u root chcon system_u:object_r:httpd_config_t:s0 /etc/httpd/conf.d/puppetmaster.conf"
   end

   if use_storeconfigs == "true"
      run "sudo -u root /etc/init.d/mysql restart"
      run "sudo -u root mysql -e 'CREATE DATABASE puppet;'"
      run "sudo -u root mysql -e \"CREATE USER 'puppet'@'localhost' IDENTIFIED BY '#{storedconfig_password}';\""
      run "sudo -u root mysql -e 'GRANT ALL PRIVILEGES ON puppet.* to \'puppet\'@\'localhost\';'"
   end

   run "sudo -u root mkdir -p #{deploy_to}/releases && sudo -u root mkdir -p #{deploy_to}/shared"
   run "sudo -u root chgrp -R #{admin_group} #{deploy_to}"
   run "sudo -u root chmod -R 2770 #{deploy_to}"
   run "ssh-keyscan -t rsa,dsa #{repo_host} github.com | sudo -u root tee /etc/ssh/ssh_known_hosts"
   run "sudo -u root #{pkg_manager} install -y #{git_pkgname}"
   run "sudo -u root chown -R #{app_user} /usr/share/puppet/rack"

   # This is retarded but, this is to make sure time syncs up with the client
   # machine, so that SSL breakage doesn't happen
   now = Time.now
   run "sudo -u root date -s '#{now}'"
end

# Before and After hooks
before "deploy:setup", :prep
after "deploy:symlink", :afterparty
after "deploy:rollback", :afterparty
before "deploy", "deploy:cleanup"
before "deploy:cleanup", :lock_deploys
after "deploy", :notify
before "notify", :unlock_deploys
after "notify", :gendocs

#vim: set expandtab ts=3 sw=3:
