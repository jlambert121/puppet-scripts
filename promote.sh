#!/usr/bin/env bash
# == Synopsis
# This is a small script that will promote the develop branches in each git
# submodule in the Puppet staging environment to master, then then pull in
# the changes to the production environment. Note that you can promote single
# commits by using the cherry-pick (-c) functionality. If you use cherry pick
# you must pass a modulename, ie 'grumps-modules' or 'manifests', with the -m
# switch
#
# == Usage
# See usage() function below
#
# == Notes
# This script does serious changes and pushes to master. Don't run it all
# willy nilly.
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
   perror "$1"
   exit $2
}

# This will go through all submodules and run the appropriate git command to
# show what commits master needs to be on track with develop. This uses the
# git cherry command, which is basically built for this exact purpose. Note
# that this had to be used due to our use case of sometimes promoting single
# changes through cherry-pick. Therefore git log master..develop would some-
# times show inaccurate information.
function list_pending_promotions() {
   pushd $puppetroot >/dev/null 2>&1

   if [ "$FORCE" != "true" ]; then
      read -p "Update checkout? (y/N) " answer
   else
      answer="N"
   fi

   if [ "$answer" != "y" -a "$answer" != "Y" ]; then
      printf "Be warned, data might be innaccurate if you are not up to date.\n"
   else
      printf "Ensure checkout is updated...\n"
      scripts/updatecheckout.sh
   fi

   printf "Show pending changes...\n\n"
   printf "========================================\n"

   # If no specific commit passed with -C, list pending promotions. If verbose
   # passed to function, all diffs listed. Lastly, if you used -C, we will only
   # spit out the diff of the specified commit.
   if [ -z "$SPECIFIC_COMMIT" ]; then
      if [ "$1" != "verbose" ]; then
         git submodule --quiet foreach 'if [[ $path =~ ^production.* ]]; then printf "%s:\n\n" "$(basename $name)"; changes=$(git checkout develop 2>/dev/null; git cherry -v master | egrep "^\+" | sed "s/^+ //"; git checkout master 2>/dev/null); if [ -z "$changes" ]; then printf "No pending commits.\n"; else printf "%s\n" "$changes"; fi; printf "========================================\n"; fi'
      else
         git submodule --quiet foreach 'if [[ $path =~ ^production.* ]]; then printf "%s:\n\n" "$(basename $name)"; changes=$(git checkout develop 2>/dev/null; git cherry -v master | egrep "^\+" | sed "s/^+ //" | cut -d" " -f1 | xargs git show; git checkout master 2>/dev/null); if [ -z "$changes" ]; then printf "No pending commits.\n"; else printf "%s\n" "$changes"; fi; printf "========================================\n"; fi'
      fi
   else
      git submodule --quiet foreach 'if [[ $path =~ ^production.* ]]; then printf "%s:\n\n" "$(basename $name)"; changes=$(git checkout develop 2>/dev/null; git cherry -v master | egrep "^\+" | sed "s/^+ //" | cut -d" " -f1 | grep "$SPECIFIC_COMMIT" | xargs git show; git checkout master 2>/dev/null); if [ -z "$changes" ]; then printf "No pending commits.\n"; else printf "%s\n" "$changes"; fi; printf "========================================\n"; fi'
   fi

   popd $puppetroot >/dev/null 2>&1
}

# Use this function to print out usage information, and exit with code of $2.
# This is useful to exit with a non-zero code due to an error in argument
# processing.
function usage() {
   printf "Usage:\n"
   printf "   %s  [-c commit -m modulename] [-h]\n" "$(basename $0)"
   printf "   -l  List all commits that master needs in all submodules. Make sure\n"
   printf "       your checkout is up to date if you run this, otherwise results may\n"
   printf "       be inaccurate.\n"
   printf "   -L  Same as -l except show full diffs rather than sha and comment\n"
   printf "   -C  If you use this in conjunction with -L, you will get only the given\n"
   printf "       SHA's diff."
   printf "   -c  Cherry pick the commit given as the argument to this switch\n"
   printf "   -f  FORCE mode- this will bypass the prompt when promoting all of staging\n"
   printf "   -h  Print this message\n"
   printf "   -m  This is required if you use -c; it is the submodule directory name\n"
   printf "   -M  This overrides the default commit message with whatever you specify\n"
   printf "\n"
   printf "Example:\n"
   printf "   %s -c d4cb267 -m manifests\n\n" "$(basename $0)"
   printf "This will cherry-pick commit d4cb267 from the manifests submodule.\n"
   printf "\n"
   printf "Example 2:\n"
   printf "   %s -f -C 5062ff83af0d6c51101e8daeb710b32ad1869ebe -l\n\n" "$(basename $0)"
   printf "This will show a diff of the given revision. Useful for CR or ticketing.\n"
   printf "\n"
   printf "Passing no arguments to this script will promote the entire staging env to\n"
   printf "production.\n"

   exit $1
}

while getopts c:C:lLfm:M:h option; do
   case "$option" in
      c)
         export COMMIT="$OPTARG"
      ;;
      C)
         export SPECIFIC_COMMIT="$OPTARG"
      ;;
      f)
         export FORCE="true"
      ;;
      h)
         usage 0
      ;;
      l)
         list_pending_promotions
         exit 0
      ;;
      L)
         list_pending_promotions verbose
         exit 0
      ;;
      m)
         export MODULE="$OPTARG"
      ;;
      M)
         export MESSAGE="$OPTARG"
      ;;
      *)
         perror "Passing bad arguments"
         usage -1
   esac
done

if [ -n "$MODULE" -a -z "$COMMIT" ]; then
   perror "You passed -m but did not pass -c, you need both."
   usage -10
fi

if [ -z "$MODULE" -a -n "$COMMIT" ]; then
   perror "You passed -c but did not pass -m, you need both."
   usage -20
fi

if [ ! -e "production/$MODULE" ]; then
   die "The module $MODULE does not exist!"
fi

# Verify whether or not commit given actually exists in develop branch
if [ -n "$COMMIT" ]; then
   pushd staging/$MODULE >/dev/null 2>&1

   if git branch --contains "$COMMIT" 2>/dev/null | grep -q develop; then
      commit_exists="true"
   else
      commit_exists="false"
   fi

   popd >/dev/null 2>&1

   if [ "$commit_exists" == "false" ]; then
      die "It appears commit $COMMIT does not exist in the develop branch of module $MODULE!"
   fi
fi

# FORCE mode in case the script is being used in a batch fashion.
if [ "$FORCE" != "true" -a -z "$COMMIT" ]; then
   read -p "Are you sure you want to promote the entire staging environment? (y/N) " answer

   if [ "$answer" != "y" -a "$answer" != "Y" ]; then
      die "Did not confirm full promotion, exiting." -5
   fi
fi

# Set commit message, dependent on whether message is passed and if cherry-
# picking or promoting the whole environment.
if [ -z "$MESSAGE" -a -n "$COMMIT" ]; then
   MESSAGE="Promote commit $COMMIT in submodule $MODULE from staging to production"
fi

if [ -z "$MESSAGE" -a -z "$COMMIT" ]; then
   MESSAGE="Promote all of staging to production."
fi

# Change dir into puppetroot with pushd so we can keep track of where we were
pushd $puppetroot >/dev/null 2>&1

# Make sure everything is up to date.
scripts/updatecheckout.sh

# Do the actual merging or cherry-picking into production and push
if [ -z "$COMMIT" ]; then
   git submodule foreach --quiet 'if [[ $path =~ ^production.* ]]; then git checkout develop && git pull && git checkout master && git merge develop && git push; fi'
else
   git submodule foreach --quiet 'if [ "$name" == "production/$MODULE" ]; then git checkout develop && git pull && git checkout master && git cherry-pick $COMMIT && git push; fi'
fi

git commit -am "$MESSAGE"
git push

popd >/dev/null 2>&1
#vim: set expandtab ts=3 sw=3:
