#!/usr/bin/env bash
# This is a silly QnD that lets you develop in the staging sub modules, then
# run this to go into each one to commit and push. Saves you some keystrokes.

export COMMIT_MESSAGE="$1"

if [ -z "$COMMIT_MESSAGE" ]; then
   printf "You must enter a commit message as the only argument to this script!\n" >&2
   exit -1
fi

git submodule foreach 'if [[ $path =~ ^staging.* ]]; then git checkout develop; git add .; if git status | tail -n 1 | grep -q "nothing to commit"; then true; else git commit -am "$COMMIT_MESSAGE" && git push -u origin develop; fi; fi'

if [ $? -eq 0 ]; then
   git commit -am "Updated submodules: $COMMIT_MESSAGE" && git push && exit 0
   exit $?
else
   printf "Error committing or pushing in submodules!\n" >&2
   exit -1
fi

#vim: set expandtab ts=3 sw=3:
