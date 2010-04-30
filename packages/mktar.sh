#!/bin/bash
########################################################################
# Script:	mktar.sh
# Description:	Creates a zipped tar archive out of the git repository.
#		This script expects to be called from "make tar" out
#		of the projects root directory!
# Author:	Jochen Gruse <jochen@zum-quadrat.de>
########################################################################

PROGRAM_NAME=${0##*/}

TAR_FOR_RPM=0

EXIT_SUCCESS=0
EXIT_ERROR=1
EXIT_BUG=2


#######################################################################
# Function:	usage
# Description:	Print usage of script and exit, if exit code is given
function usage {
	[ $# -gt 0 ] && EXITCODE="$1"
	echo "Usage: $PROGRAM_NAME [-r]" >&2
	# More at a later time
	[ -n "$EXITCODE" ] && exit "$EXITCODE"
}


########################################################################
# Main
########################################################################
while getopts ':r' OPTION ; do
	case $OPTION in
	r) TAR_FOR_RPM=1
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


if [ $TAR_FOR_RPM -eq 0 ] ; then
	VERSION=$( ./print_version.sh )
else
	VERSION=$( ./print_version.sh -v )
fi
FULL_PACKAGE_NAME=gsm-ussd_${VERSION}


(
	cd ..
	git archive --prefix="${FULL_PACKAGE_NAME}/" HEAD
) | \
gzip -9 > ${FULL_PACKAGE_NAME}.tar.gz

exit $EXIT_SUCCESS
