#!/bin/bash
########################################################################
# Script:	gussd.sh
# Description:	Prototype of a GUI for gsm-ussd
# Author:	Jochen Gruse
# External dependencies:	(Package)
#		grep		(grep)
#		zenity		(zenity)
#		gsm-ussd	(gsm-ussd)
########################################################################


########################################################################
# Function:	show_progressbar
# Description:	Fakes a "progress" bar.
function show_progressbar {

	
        trap 'kill $ZENITY_PID; return 0' 0 2 15

	yes | zenity \
		--title "$TITLE" \
		--progress \
		--pulsate &
	ZENITY_PID=$!

	wait

	return 0
}


########################################################################
# Function:	escape_markup
# Description:	Translates in its stdin
#		every & into &amp;
#		every < into &lt;
#		every > into &gt;
#		and writes the resulting text to stdout
function escape_markup {
	sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}


########################################################################
# Function:	show_progressbar
# Description:	Fakes a "progress" bar.
########################################################################
# MAIN
########################################################################

# Name of this script, used in dialog titles
TITLE=${0##*/}

# Any options are given over to gsm-ussd. No checking done here!
GSM_USSD_OPTS="$@"

# -p/--pin already given? Then we don't have to ask by dialog box
# This is only an approximation, the legal grouping
#	-cdp 1234
# is not recognized
PIN_NEEDED=1
if echo "$GSM_USSD_OPTS" | grep -Eq -- '-p|--pin' ; then
	PIN_NEEDED=0
fi

# Ask for USSD query, set "*100#" as default
USSD_QUERY=$(			
	zenity \
	--title "$TITLE" \
	--entry \
	--text 'Please enter the USSD query you would like to send:' \
	--entry-text '*100#' \
	# 2>&-
)
if [ $? -ne 0 ] ; then
	exit 1
fi

# Ask for PIN, if needed
PIN_OPT=""
if [ $PIN_NEEDED -eq 1 ] ; then
	PIN=$(
		zenity \
		--title "$TITLE" \
		--entry \
		--text 'Please enter your PIN for your SIM card. If no PIN is needed, leave blank.' \
		--hide-text \
		# 2>&-
	)
	if [ $? -eq 0 -a -n "$PIN" ] ; then
		PIN_OPT="-p $PIN"
	fi
fi

# Start the progress bar display
show_progressbar &
PROGRESS_PID=$!

# Do the actual work
RESULT=$( gsm-ussd $PIN_OPT $GSM_USSD_OPTS "$USSD_QUERY" 2>&1 )
GSM_USSD_EXITCODE=$?

# End progress bar display (if not already gone)
kill $PROGRESS_PID >&- 2>&-

# Show gsm-ussd result in appropiate dialog box
if [ $GSM_USSD_EXITCODE -ne 0 ] ; then
	DIALOG_TYPE="--error"
else
	DIALOG_TYPE="--info"
fi
zenity --title "$TITLE" $DIALOG_TYPE --text "$(echo $RESULT | escape_markup )"

exit 0
