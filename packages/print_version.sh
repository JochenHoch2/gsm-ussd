#!/bin/bash
#######################################################################
# Script:	print_version.sh
# Description:	Prints a version number made up of a mangled 
#		"git describe" output. A leading "v" and the appended
#		commit SHA are stripped.
#		As simple as this script is, it's still better done
#		separately here as in a copy in every script.
# Author:	Jochen Gruse <jochen@zum-quadrat.de>
#######################################################################

git describe | \
sed -e 's/^v//' -e 's/-[^-]*$//'
