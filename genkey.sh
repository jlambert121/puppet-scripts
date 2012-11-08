#!/bin/bash
workdir="$HOME/working"
pupdir="$workdir/git/puppet"
ssldir="$pupdir/ssl"

if [ $# -lt 1 ]; then
   echo "Please enter a hostname"
   exit -1
fi

# Sometimes, if /var/run/puppet isn't available, this script will not work.
if ! [ -e '/var/run/puppet' ]; then
   sudo mkdir /var/run/puppet
fi

for node in $@; do
   puppet cert --certname puppet --ssldir $ssldir --confdir $pupdir --keylength 4096 -g $node
done

# Descend into ssldir, commit update to submodule, then go back up and update
# the parent.
pushd $pupdir >/dev/null 2>&1
pushd $ssldir >/dev/null 2>&1
git add . 
git commit -am "Added key(s) for nodes #SEC" --no-verify
git push
popd >/dev/null 2>&1
git add ssl
git commit -m "Updated SSL submodule" --no-verify
git push
popd >/dev/null 2>&1

#vim: set expandtab ts=3 sw=3:
