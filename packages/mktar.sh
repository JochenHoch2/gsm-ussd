#!/bin/bash
########################################################################
# Script:	mktar.sh
# Description:	Creates a zipped tar archive out of the git repository.
#		This script expects to be called from "make tar" out
#		of the projects root directory!
# Author:	Jochen Gruse <jochen@zum-quadrat.de>
########################################################################
VERSION=$( ./print_version.sh )
(
	cd ..
	git archive --prefix="gsm-ussd_${VERSION}/" HEAD
) | \
gzip -9 > gsm-ussd_${VERSION}.tar.gz
