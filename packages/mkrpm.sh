#!/bin/bash
########################################################################
# Script:	mkrpm.sh
# Description:	Creates a RPM build infrastructure, populates it with
#		all needed files and builds a binary noarch RPM file
#		containing the gsm-ussd project.
# Author:	Jochen Gruse <jochen@zum-quadrat.de> 
########################################################################

# Clean up while exiting
trap 'rm -rf rpm ; exit 0' 0

# Create work directory
mkdir -p rpm/SOURCES rpm/SPECS rpm/BUILD rpm/RPMS rpm/BUILDROOT rpm/SRPMS

# Get project version and release
VERSION=$( ./print_version.sh -v )
RELEASE=$( ./print_version.sh -r )

BASE_FILENAME="gsm-ussd_${VERSION}"
SPEC_FILE="rpm/SPECS/${BASE_FILENAME}.spec"
TAR_FILE="${BASE_FILENAME}-${RELEASE}.tar.gz"

# Populate build directories with .{spec,tar.gz} files
sed	-e '/^ *#/d' \
	-e 's/@@VERSION@@/'${VERSION}'/' \
	-e 's/@@RELEASE@@/'${RELEASE}'/' \
	spec.tmpl >$SPEC_FILE

mv $TAR_FILE rpm/SOURCES

# Create RPM package
rpmbuild --define "_topdir $PWD/rpm" -bb $SPEC_FILE

# Save RPM package
mv rpm/RPMS/noarch/*.rpm .

# Cleanup will happen on exit
exit 0
