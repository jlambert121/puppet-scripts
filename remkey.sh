#!/bin/bash
pupdir="$HOME/working/git/puppet"
ssldir="$pupdir/ssl"

if [ $# -lt 1 ]; then
   echo "Please enter a hostname"
   exit -1
fi

for node in $@; do
   puppet cert --certname puppet --confdir $pupdir --ssldir $ssldir --revoke $node
   puppet cert --certname puppet --confdir $pupdir --ssldir $ssldir --clean $node
done

# Descend into ssldir, commit update to submodule, then go back up and update
# the parent.
pushd $pupdir >/dev/null 2>&1
pushd $ssldir >/dev/null 2>&1
git add . 
git commit -am "Removed key(s) for nodes #SEC" --no-verify
git push
popd >/dev/null 2>&1
git add .
git commit -am "Updated SSL submodule" --no-verify
git push
popd >/dev/null 2>&1
printf "Please don't forget to remove the node(s) from stored configs on its master.\n"

#vim: set expandtab ts=3 sw=3:
