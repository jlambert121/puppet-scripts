#!/usr/bin/env ruby
# == Synopsis
# These are some constants that can be used for common error codes. I hope
# this isn't duplicated in the API itself. Error codes are kind of out of
# vogue but I do enjoy the ability to use them and easily find out what
# one means in documentation.
#
# == Notes
# This is required by aws-config.rb usually.
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

EREGIONNOTFOUND         = 101
ECFGFORMAT              = 102
ENOHOSTS                = 103
ENOIMAGEID              = 104
ENOSECGROUP             = 105
ECFGREAD                = 106
ENONODES                = 107
EUNKNOWN                = 201

#vim: set expandtab ts=3 sw=3:
