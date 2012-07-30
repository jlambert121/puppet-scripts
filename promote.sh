#!/usr/bin/env bash
# == Synopsis
# This is a small script that will promote the develop branches in each git
# submodule in the Puppet staging environment to master, then then pull in
# the changes to the production environment. Note that you can promote single
# commits by using the cherry-pick (-c) functionality. If you use cherry pick
# you must pass a modulename, ie 'grumps-modules' or 'manifests', with the -m
# switch. You can also promote sets of changes related to a ticket, as long
# as the developer remembers to put the ticket number in the commit message.
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

   # Unlock deploys now that we are dying
   bypass_tests="true" cap unlock_deploys || perror "Unable to unlock deploys, please investigate."

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
      printf "Ensure checkout is updated... "
      scripts/updatecheckout.sh >/dev/null 2>&1 || die "FAILURE! check updatecheckout.sh works!"
      printf "SUCCESS!\n"
   fi

   if ! [ -n "$TICKET" -a "$1" != "verbose" ]; then
      printf "Show pending changes...\n\n"
      printf "========================================\n"
   fi

   # If no specific commit passed with -C, list pending promotions. If verbose
   # passed to function, all diffs listed. Then, if you passed a ticket, list
   # pending promotions related to ticket, and if verbose list related diffs.
   # Lastly, if you used -C, we will only spit out the diff of the specified
   # commit if you specified a commit.
   if [ -z "$SPECIFIC_COMMIT" -a -z "$TICKET" ]; then
      if [ "$1" != "verbose" ]; then
         git submodule --quiet foreach 'if [[ $path =~ ^production.* ]]; then printf "%s:\n\n" "$(basename $name)"; changes=$(git checkout develop 2>/dev/null; git cherry -v master | egrep "^\+" | sed "s/^+ //"; git checkout master 2>/dev/null); if [ -z "$changes" ]; then printf "No pending commits.\n"; else printf "%s\n" "$changes"; fi; printf "========================================\n"; fi'
      else
         git submodule --quiet foreach 'if [[ $path =~ ^production.* ]]; then printf "%s:\n\n" "$(basename $name)"; changes=$(git checkout develop 2>/dev/null; git cherry -v master | egrep "^\+" | sed "s/^+ //" | cut -d" " -f1 | xargs git show; git checkout master 2>/dev/null); if [ -z "$changes" ]; then printf "No pending commits.\n"; else printf "%s\n" "$changes"; fi; printf "========================================\n"; fi'
      fi
   elif [ -n "$TICKET" ]; then
      if [ "$1" != "verbose" ]; then
         git submodule --quiet foreach 'if [[ $path =~ ^production.* ]]; then changes=$(git checkout develop 2>/dev/null; git cherry -v master | grep "#${TICKET}" | egrep "^\+" | sed "s/^+ //" | sed "s/^/$(basename $name) /"; git checkout master 2>/dev/null); if [ -n "$changes" ]; then printf "%s\n" "$changes"; fi; fi'
      else
         git submodule --quiet foreach 'if [[ $path =~ ^production.* ]]; then printf "%s:\n\n" "$(basename $name)"; changes=$(git checkout develop 2>/dev/null; git cherry -v master | grep "#${TICKET}" | egrep "^\+" | sed "s/^+ //" | cut -d" " -f1 | xargs git show; git checkout master 2>/dev/null); if [ -z "$changes" ]; then printf "No pending commits.\n"; else printf "%s\n" "$changes"; fi; printf "========================================\n"; fi'
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
   printf "       SHA's diff.\n"
   printf "   -c  Cherry pick the commit given as the argument to this switch\n"
   printf "   -f  FORCE mode- this will bypass the prompt when promoting all of staging\n"
   printf "   -m  This is required if you use -c; it is the submodule directory name\n"
   printf "   -M  This overrides the default commit message with whatever you specify\n"
   printf "   -t  Specify a ticket number as an argument to this. Note that you can use\n"
   printf "       this in conjunction with -L to get all the diffs related to a ticket,\n"
   printf "       or you can use it with -c to promote all changes related to a ticket.\n"
   printf "   -h  Print this message\n"
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

while getopts c:C:lLfm:M:t:h option; do
   case "$option" in
      h)
         usage 0
      ;;
      c)
         export COMMIT="$OPTARG"
      ;;
      C)
         export SPECIFIC_COMMIT="$OPTARG"
      ;;
      f)
         export FORCE="true"
      ;;
      l)
         export LIST_PENDING="true"
      ;;
      L)
         export LIST_PENDING_VERBOSE="true"
      ;;
      m)
         export MODULE="$OPTARG"
      ;;
      M)
         export MESSAGE="$OPTARG"
      ;;
      t)
         export TICKET="$OPTARG"
      ;;
      *)
         perror "Passing bad arguments"
         usage -1
   esac
done

# If you wanted to list AND list verbose, print error, verbose wins.
if [ "$LIST_PENDING" == "true" -a "$LIST_PENDING_VERBOSE" == "true" ]; then
   perror "You passed both -l and -L; -L takes precedence"
fi

# If ticket specified, ensure it is a number. When LH API gets used, could
# even check if the ticket is valid.
if [ -n "$TICKET" ]; then
   if ! echo "$TICKET" | egrep -q '^[[:digit:]]+$'; then
      die "You specified a garbage string for a ticket number: $TICKET"
   fi
fi

# Check for logical errors when parsing args.
# Passing a module but no ticket or commit.
if [ -n "$MODULE" -a -z "$COMMIT" -a -z "$TICKET" ]; then
   perror "You passed -m but did not pass -c or -t, you need both."
   usage -10
fi

# Passing a commit but no module
if [ -z "$MODULE" -a -n "$COMMIT" ]; then
   perror "You passed -c or -t, but did not pass -m, you need both."
   usage -20
fi

# Passing a ticket and a commit, fail... this is very important, as a lot of
# subsequent logic relies on this test failing execution before its reached.
if [ -n "$COMMIT" -a -n "$TICKET" ]; then
   perror "You passed both a ticket (-t), AND a commit (-c). Use one or the other."
   usage -21
fi

# Previous test for cherry picking (-c) and ticket (-t) failure. This test
# ensures that for listing promotions, you don't pass -C and -t, which doesn't
# make sense.
if [ -n "$SPECIFIC_COMMIT" -a -n "$TICKET" ]; then
   perror "You passed both a ticket (-t), and a commit SHA to cherry-pick (-C)."
   usage -22
fi

# Call list functions and quit if options passed
if [ "$LIST_PENDING_VERBOSE" == "true" ]; then
   list_pending_promotions verbose
   exit 0
fi

if [ "$LIST_PENDING" == "true" ]; then
   list_pending_promotions
   exit 0
fi

# This check seems off, but it will pass if no module is entered, and
# will fail if an erroneous module is passed.
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
if [ "$FORCE" != "true" -a -z "$COMMIT" -a -z "$TICKET" ]; then
   read -p "Are you sure you want to promote the entire staging environment? (y/N) " answer

   if [ "$answer" != "y" -a "$answer" != "Y" ]; then
      die "Did not confirm full promotion, exiting." -5
   fi
fi

# Set commit message, dependent on whether message is passed and if cherry-
# picking or promoting the whole environment.
if [ -z "$MESSAGE" -a -n "$COMMIT" ]; then
   export MESSAGE="Promote commit $COMMIT in submodule $MODULE from staging to production"
elif [ -z "$MESSAGE" -a -n "$TICKET" ]; then
   export MESSAGE="Promote all commits related to ticket [#$TICKET] from staging to production"
elif [ -z "$MESSAGE" -a -z "$COMMIT" -a -z "$TICKET" ]; then
   export MESSAGE="Promote all of staging to production."
else
   die "Could not formulate a proper MESSAGE for the commit, investigate around line 254+"
fi

# Change dir into puppetroot with pushd so we can keep track of where we were
pushd $puppetroot >/dev/null 2>&1

# Make sure everything is up to date.
printf "Ensure checkout is updated... "
scripts/updatecheckout.sh >/dev/null 2>&1 || die "FAILURE! check updatecheckout.sh works!"
printf "SUCCESS!\n"

# Lock deploys with message to ensure the promotion isn't deployed at an
# inopportune time.
bypass_tests="true" lock_reason="$MESSAGE" cap lock_deploys || die "Error locking deploys! Not safe to continue!"

# Do the actual merging or cherry-picking into production and push
if [ -z "$COMMIT" -a -z "$TICKET" ]; then
   git submodule foreach --quiet 'if [[ $path =~ ^production.* ]]; then git checkout develop && git pull && git checkout master && git merge -m "$MESSAGE" develop && git push; fi' || die "It appears that the whole staging merge failed!"
elif [ -n "$TICKET" ]; then
   # Get space-separated list of commits related to ticket number
   export PENDING_PROMOTIONS=$(FORCE=true list_pending_promotions | sed 1d)

   # FORCE mode in case the script is being used in a batch fashion.
   if [ "$FORCE" != "true" ]; then
      printf "This operation will promote %d commits:\n\n%s\n\n" "$(echo "$PENDING_PROMOTIONS" | wc -l)" "$PENDING_PROMOTIONS"

      read -p "Are you sure you want to promote all commits associated with ticket $TICKET? (y/N) " answer

      if [ "$answer" != "y" -a "$answer" != "Y" ]; then
         die "Did not confirm multi-commit promotion, exiting." -5
      fi
   fi

   # In each submodule, Grep PENDING_PROMOTIONS for current submodule, cherry-pick all of field 2
   git submodule foreach --quiet 'if [[ $name =~ ^production ]]; then export COMMITS=$(echo "$PENDING_PROMOTIONS" | grep "$(basename $name)" | cut -d" " -f2 | tr "\n" " "); if [ -n "$COMMITS" ]; then git checkout develop && git pull && git checkout master && git cherry-pick $COMMITS && git push; fi; fi' || die "It appears the cherry-pick of commits $COMMITS failed!"
else
   git submodule foreach --quiet 'if [ "$name" == "production/$MODULE" ]; then git checkout develop && git pull && git checkout master && git cherry-pick $COMMIT && git push; fi' || die "It appears the cherry-pick of commit $COMMIT failed!"
fi

printf "Running puppet-test, output will go in commit message of super-project... "

export FAILCOUNT=0
export TESTINGRESULTS="$($puppetroot/scripts/puppet-test -d -e testing 2>&1)"
((FAILCOUNT+=$?))
export STAGINGRESULTS="$($puppetroot/scripts/puppet-test -d -e staging 2>&1)"
((FAILCOUNT+=$?))

if [ $FAILCOUNT -eq 0 ]; then
   MESSAGE=$(printf '%s\n\n%s\n%s:\n\n%s\n%s' "$MESSAGE" "===============================================================================" "Puppet Tests for Testing Environment" "$TESTINGRESULTS" "===============================================================================")
   MESSAGE=$(printf '%s\n%s:\n\n%s\n%s' "$MESSAGE" "Puppet Tests for Staging Environment" "$STAGINGRESULTS" "===============================================================================")

   printf "SUCCESS!\n"
   git commit -am "$MESSAGE"
   git push
else
   printf "FAILURE!\n"
   printf "Please run puppet-test -d -e staging (and testing), fix the errors, then re-attempt promotion!\n"
fi

# Unlock deploys now that we are finished.
bypass_tests="true" cap unlock_deploys || perror "Unable to unlock deploys, please investigate."

popd >/dev/null 2>&1
#vim: set expandtab ts=3 sw=3:
