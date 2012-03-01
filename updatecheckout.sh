#!/usr/bin/env bash
# == Synopsis
# This is a small script that will update your whole checkout.
#
# == Usage
# See usage() function below.
#
# == Notes
# Don't eat the yellow snow.
#
# == Authors
# Joe McDonagh <jmcdonagh@thesilentpenguin.com>
#
# == Copyright
# 2012 The Silent Penguin LLC
#
# == License
# Licensed under the BSD license
#

puppetroot="$HOME/working/git/puppet"

# Useful helper function, shorthand for cat'ing files that have error output
function caterror() {
   cat "$1" >&2
}

# Like caterror, shorthand for sending strings to stderr
function perror() {
   printf "%s\n" "$1" >&2
}

# Print a fatal error and exit with exit code $2
function die() {
   perror "%s\n" "$1"
   exit $2
}

# Change dir into puppetroot with pushd so we can keep track of where we were
pushd $puppetroot >/dev/null 2>&1

# Make sure everything is up to date.
git pull --all
git submodule update --merge
git submodule foreach --quiet 'if [[ $path =~ ^staging.* ]]; then git checkout develop && git pull; fi'
git submodule foreach --quiet 'if [[ $path =~ ^production.* ]]; then git checkout master && git pull && git checkout develop && git pull && git checkout master; fi'

popd >/dev/null 2>&1
#vim: set expandtab ts=3 sw=3:
