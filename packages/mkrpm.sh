#!/bin/bash

# trap 'rm -rf rpm ; exit 0' 0

mkdir -p rpm/SPECS rpm/BUILD rpm/SOURCES rpm/RPMS rpm/BUILDROOT

FULL_VERSION=$( ./print_version.sh )
VERSION=${FULL_VERSION%-*}
RELEASE=${FULL_VERSION##*-}

RPMRC_FILES="/usr/lib/rpm/rpmrc:/usr/lib/rpm/redhat/rpmrc:/etc/rpmrc:~/.rpmrc:./rpmrc"

SPEC_FILE=gsm-ussd_${VERSION}.spec

sed -e 's/@@VERSION@@/'${VERSION}'/' -e 's/@@RELEASE@@/'${RELEASE}'/'  spec.tmpl >rpm/SPECS/$SPEC_FILE

rpmbuild --rcfile="$RPMRC_FILES" -ba $SPEC_FILE
