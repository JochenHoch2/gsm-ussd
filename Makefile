########################################################################
# Makefile for gsm_ussd.pl
########################################################################

# Where to install by default
PREFIX		= /usr/local

# Used paths
INSTALL_PATH	= $(PREFIX)
BIN_PATH	= $(INSTALL_PATH)/bin
MAN_PATH	= $(INSTALL_PATH)/share/man
LIB_PATH	= $(INSTALL_PATH)/lib/gsm-ussd

# The documentation in POD and *roff format
PODS		= docs/gsm-ussd.en.pod docs/gsm-ussd.de.pod docs/xussd.en.pod docs/xussd.de.pod
MANS		= $(PODS:.pod=.man)

.PHONY:		install install-doc all clean

# Nothing to do for scripts, just build docs
all:		doc

install:	all
	install -d $(BIN_PATH)
	install -d $(LIB_PATH)/bin
	install -d $(LIB_PATH)/lib/GSMUSSD
	install lib/GSMUSSD/* $(LIB_PATH)/lib/GSMUSSD
	install bin/gsm-ussd.pl $(LIB_PATH)/bin
	install bin/xussd.sh $(LIB_PATH)/bin
	cd $(BIN_PATH) && ln -sf ../lib/gsm-ussd/bin/gsm-ussd.pl gsm-ussd
	cd $(BIN_PATH) && ln -sf ../lib/gsm-ussd/bin/xussd.sh xussd

doc:	$(MANS)

install-doc:	doc
	install docs/gsm-ussd.en.man $(MAN_PATH)/man1/gsm-ussd.1
	install docs/gsm-ussd.de.man $(MAN_PATH)/de/man1/gsm-ussd.1
	install docs/xussd.en.man $(MAN_PATH)/man1/xussd.1
	install docs/xussd.de.man $(MAN_PATH)/de/man1/xussd.1

# How to create man pages out of POD files
%.man:	%.pod 
	pod2man --name `echo $< | perl -p -e 's-.*/([^.]*)\..*-\U\1-'` $< > $@

# Create ready-made packages out of the git repository
tar:		doc
	cd packages && ./mktar.sh

deb:		doc
	cd packages && ./mkdeb.sh

rpm:		doc
	cd packages && ./mkrpm.sh

publish:	clean rpm deb tar
	cd packages && ncftpput -f ~/.ftp /linux/downloads gsm-ussd*

clean:
	rm -f docs/*.man
	rm -f packages/*.deb
	rm -f packages/*.tar.gz
	rm -f packages/*.spec
	rm -f packages/*.rpm
