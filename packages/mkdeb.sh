#!/bin/bash
########################################################################
# Script:	mkdeb.sh
# Description:	This shell script creates the infrastructure for a 
#		debian package, populates it with files of the gsm-ussd
#		project, builds the .deb file and cleans up.
#		It is meant to be used to fulfill the "deb" target of
#		the top level Makefile.
#		It expects all files of the gsm-ussd project to have 
#		been built.
# Author:	Jochen Gruse <jochen@zum-quadrat.de>
########################################################################

# Just for development & debugging
CLEANUP=1
if [ $# -eq 1 -a "x$1" = "x-n" ] ; then
	CLEANUP=0
fi

VERSION=$( ./print_version.sh )

# Install paths for gsm-ussd files in .deb file
BASE_PATH=gsm-ussd_${VERSION}_all
BIN_PATH=$BASE_PATH/usr/bin
MAN_EN_PATH=$BASE_PATH/usr/share/man/man1
MAN_DE_PATH=$BASE_PATH/usr/share/man/de/man1
DEBIAN_PATH=$BASE_PATH/DEBIAN
DOC_PATH=$BASE_PATH/usr/share/doc/gsm-ussd


########################################################################
# Create directory tree for .deb file
########################################################################
function create_installation_directories {
	(
		set -e
		mkdir -p $BIN_PATH
		mkdir -p $MAN_EN_PATH
		mkdir -p $MAN_DE_PATH
		mkdir -p $DEBIAN_PATH
		mkdir -p $DOC_PATH
	) 2>/dev/null
	if [[ $? -ne 0 ]] ; then
		echo "Could not create installation directories - abort" >&2
		exit 1
	fi
	return 0
}


########################################################################
# Create md5sums of all files in directory tree
########################################################################
function create_md5sums {
	( cd $BASE_PATH && \
	find usr -type f -print0 | \
	xargs -0 md5sum > ../$DEBIAN_PATH/md5sums )
}


########################################################################
# Copy all needed files of gsm-ussd into the directory tree for .deb
########################################################################
function copy_gsm-ussd_files {
	(
		set -e

		# Binaries
		cp ../gsm-ussd.pl $BIN_PATH/gsm-ussd
		cp ../xussd.sh $BIN_PATH/xussd

		# Man pages
		cp ../docs/gsm-ussd.en.man $MAN_EN_PATH/gsm-ussd.1
		cp ../docs/gsm-ussd.de.man $MAN_DE_PATH/gsm-ussd.1
		cp ../docs/xussd.en.man $MAN_EN_PATH/xussd.1
		cp ../docs/xussd.de.man $MAN_DE_PATH/xussd.1
		gzip --best $MAN_EN_PATH/gsm-ussd.1
		gzip --best $MAN_DE_PATH/gsm-ussd.1
		gzip --best $MAN_EN_PATH/xussd.1
		gzip --best $MAN_DE_PATH/xussd.1
		
		# Supplementary docs
		cp ../LICENSE $DOC_PATH/copyright
		cp ../docs/README.en $DOC_PATH
		cp ../docs/README.de $DOC_PATH
		cp ../docs/story.txt $DOC_PATH
		cp ../docs/ussd-sessions.txt $DOC_PATH
		cp ../README $DOC_PATH
		cp ../TODO $DOC_PATH
		cp ../INSTALL $DOC_PATH
		git log > $DOC_PATH/changelog
		cat > $DOC_PATH/changelog.Debian <<-'EOF'
		gsm-ussd (0.1.0-1) karmic lucid; urgency=low

		  * This file will not be updated
		    Please see normal changelog file for updates,
		    as Debian maintainer and upstream author are identical.

		 -- Jochen Gruse <jochen@zum-quadrat.de>  Wed, 21 Apr 2010 22:59:36 +0200

		EOF
		gzip --best $DOC_PATH/changelog
		gzip --best $DOC_PATH/changelog.Debian

		# Debian control and support files
		sed -e 's/@@VERSION@@/'$VERSION'/' control.tmpl > $DEBIAN_PATH/control
		create_md5sums
	) 2>/dev/null
	if [ $? -ne 0 ] ; then
		echo "Could not copy installation files - abort" >&2
		exit 1
	fi
	return 0
}


########################################################################
# Build the .deb file
########################################################################
function build_deb_package {
	fakeroot dpkg-deb --build $BASE_PATH
}


########################################################################
# Remove directory tree after building .deb file
########################################################################
function clean_up {
	rm -rf $BASE_PATH
}


########################################################################
# Main
########################################################################

create_installation_directories

copy_gsm-ussd_files

build_deb_package

[ $CLEANUP -eq 1 ] && clean_up

exit 0
