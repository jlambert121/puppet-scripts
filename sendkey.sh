#!/bin/bash
if [ "$1" = "new" -a -z "$username" ]; then
   export username="bmadmin"
   shift
elif [ -n "$username" ]; then
   export username=$username
else
   export username=$USER
fi

if [ -z "$1" ]; then
   printf "Please specify a node\n"
fi

export PUPPET_CHECKOUT="$HOME/working/git/puppet"

for node in $@; do
   if ! [ -e "$PUPPET_CHECKOUT/ssl/ca/signed/$node.pem" ]; then
      printf "Node %s's cert has not been generated, next!\n" "$node" >&2
   fi

   if ! nc -w 3 -z "$node" 22; then
      printf "Could not connect to %s\n" "$node" >&2
      continue
   fi

   kernel="$(ssh -o 'StrictHostKeyChecking=no' -t $username@$node 'facter kernel 2>/dev/null | head -n 1 | tr [:upper:] [:lower:]' | tr -d '\r')"

   case $kernel in
      openbsd)
         puppet_group="_puppet"
         startcmd="sudo -u root puppet agent"
         vardir="/var/puppet"
      ;;
      *)
         puppet_group="puppet"
         startcmd="sudo -u root /etc/init.d/puppet start"
         vardir="/var/lib/puppet"
      ;;
   esac

   escaped_vardir="$(echo $vardir | sed 's/\//\\\//g')"

   ssh -o 'StrictHostKeyChecking=no' -t $username@$node "sudo -u root pkill -f 'puppet agent' || sudo -u root pkill -9 -f 'puppet agent'"
   ssh -o 'StrictHostKeyChecking=no' -t $username@$node "sudo -u root rm -rf $vardir/ssl /etc/puppet/ssl"
   ssh -o 'StrictHostKeyChecking=no' -t $username@$node "mkdir -p /tmp/ssl/{ca,certs,private_keys,public_keys} && mkdir /tmp/ssl/ca/signed"
   sudo rm -f /tmp/puppet.conf.erb
   cp $PUPPET_CHECKOUT/production/grumps-modules/puppet/templates/node/puppet.conf.erb /tmp/puppet.conf.erb

   # So dirty, sets up testing/staging puppet.conf for nodes named x-staging or x-testing.
   node_env=$(echo $node | cut -d'.' -f1 | cut -d'-' -f2)

   if [ -z "$node_env" -o "$node_env" == "$(echo $node | cut -d'.' -f1)" ]; then
      node_env="production"
   fi

   gsed -i "s/<%= scope.lookupvar(\"::environment\") %>/$node_env/g" /tmp/puppet.conf.erb

   scp -o 'StrictHostKeyChecking=no' "/tmp/puppet.conf.erb" $username@$node:/tmp/puppet.conf
   scp -o 'StrictHostKeyChecking=no' "$PUPPET_CHECKOUT/ssl/ca/signed/$node.pem" $username@$node:"/tmp/ssl/ca/signed/$node.pem"
   scp -o 'StrictHostKeyChecking=no' "$PUPPET_CHECKOUT/ssl/private_keys/$node.pem" $username@$node:"/tmp/ssl/private_keys/$node.pem"
   scp -o 'StrictHostKeyChecking=no' "$PUPPET_CHECKOUT/ssl/public_keys/$node.pem" $username@$node:"/tmp/ssl/public_keys/$node.pem"
   scp -o 'StrictHostKeyChecking=no' "$PUPPET_CHECKOUT/ssl/certs/ca.pem" $username@$node:"/tmp/ssl/certs/ca.pem"
   ssh -o 'StrictHostKeyChecking=no' -t $username@$node "sudo -u root cp -p /tmp/ssl/ca/signed/$node.pem /tmp/ssl/certs/ && sudo -u root rm -rf $vardir/ssl"
   ssh -o 'StrictHostKeyChecking=no' -t $username@$node "sed -e '/^<%.*$/d' -e 's/\(vardir.*= \).*$/\1${escaped_vardir}/' /tmp/puppet.conf | sudo -u root uniq - /etc/puppet/puppet.conf"
   ssh -o 'StrictHostKeyChecking=no' -t $username@$node "sudo -u root chown -R root:${puppet_group} /tmp/ssl && sudo -u root mv -f /tmp/ssl $vardir/ && sudo -u root cp -Rp $vardir/ssl /etc/puppet/"
   ssh -o 'StrictHostKeyChecking=no' -t $username@$node "sudo -u root sed -i 's/no/yes/g' /etc/default/puppet; $startcmd"
done

#vim: set expandtab ts=3 sw=3:
