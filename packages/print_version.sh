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

PROGRAM_NAME=${0##*/}

#######################################################################
# Function:	usage
# Description:	Print usage of script and exit, if exit code is given
function usage {
	[ $# -gt 0 ] && EXITCODE="$1"
	echo "Usage: $PROGRAM_NAME [-f] [-r] [-v] [-v]" >&2
	# More at a later time
	[ -n "$EXITCODE" ] && exit "$EXITCODE"
}

########################################################################
# Function:	running_in_git_repo
# Description	Checks whether 
#			* git is available
#			* we are in a git repo
#		and returns corresponding exit code
function running_in_git_repo {
	if which git >/dev/null 2>&1 ; then
		if git log >/dev/null 2>&1 ; then
			# git installed, in git repo
			return 0
		else
			# git installed, but not in git repo
			return 1
		fi
	else
		# git not even installed
		return 1
	fi
	# NOTREACHED
        echo "This could not have happened - unexpected fall-thru in $FUNCNAME" >&2
}


########################################################################
# Main
########################################################################

VERSION_TYPE=full

EXIT_SUCCESS=0
EXIT_ERROR=1
EXIT_BUG=2

while getopts ':frvh' OPTION ; do
	case $OPTION in
	f) VERSION_TYPE=full
	;;
	r) VERSION_TYPE=release
	;;
	v) VERSION_TYPE=version
	;;
	h) usage $EXIT_SUCCESS
	;;
	\?) echo "Unknown option \"-$OPTARG\"." >&2
	usage $EXIT_ERROR
	;;
	*) echo "This could not have happened - unknown and unhandled option." >&2
 	usage $EXIT_BUG
	;;
	esac
done
# Verbrauchte Argumente überspringen
shift $(( OPTIND - 1 ))


if running_in_git_repo ; then
	RELEASE=$(
		git describe | \
		sed -e 's/^v[^-]*-//' -e 's/-g[^-]*$//'
	)
	if [ -n "$RELEASE" ] ; then
		RELEASE=0
	fi
	VERSION=$(
		git describe --abbrev=0 | \
		sed -e 's/^v//'
	)
else
	RELEASE=0
	VERSION=$(
		awk '
			/our +\$VERSION *=/ {
				if (match ($0, /[0-9.]+/) ) {
					print substr ($0, RSTART, RLENGTH)
					exit 0
				}
			}
		' \
		../gsm-ussd.pl
	)
	
	if [ -n "$VERSION" ] ; then
		echo "This should not have happened - cannot find version number." >&2
		exit $EXIT_ERROR
	fi
fi

case $VERSION_TYPE in
full)
	echo "$VERSION-$RELEASE"
	;;
release)
	echo "$RELEASE"
	;;
version)
	echo "$VERSION"
	;;
*)
	echo "This could not have happened - unknown requested version type" >&2
	usage $EXIT_BUG
	;;
esac

exit $EXIT_SUCCESS
