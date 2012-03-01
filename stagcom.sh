#!/usr/bin/env bash
# This is a silly QnD that lets you develop in the staging sub modules, then
# run this to go into each one to commit and push. Saves you some keystrokes.
# Force needs to be used sometimes to really push things. What force does is
# just change the command chain to use ; instead of &&. What happens I think
# is the ordering of foreach sometimes will try to commit somewhere it should
# not first. I have yet to encounter an issue force didn't fix, unless you've
# made a big mistake and did something like committing in prod first or what-
# ever other wacky mistakes you may make when you first learning these tools
# and git submodules.

export COMMIT_MESSAGE="$1"

if [ -z "$COMMIT_MESSAGE" ]; then
   printf "You must enter a commit message as the only argument to this script!\n" >&2
   exit -1
fi

if [ "$2" == "force" ]; then
   printf "Forcing the operation...\n"
   git submodule foreach 'if [[ $path =~ ^staging.* ]]; then git checkout develop; git add .; git commit -am "$COMMIT_MESSAGE"; git push -u origin develop; fi'
else
   git submodule foreach 'if [[ $path =~ ^staging.* ]]; then git checkout develop && git add . && git commit -am "$COMMIT_MESSAGE" && git push -u origin develop; fi'
fi

git commit -am "Updated submodules: $COMMIT_MESSAGE"
git push

#vim: set expandtab ts=3 sw=3:
