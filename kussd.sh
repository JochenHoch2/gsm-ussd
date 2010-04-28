#!/bin/bash
########################################################################
# Script:	kussd.sh
# Description:	Prototype of a GUI for gsm-ussd
# Author:	Jochen Gruse
########################################################################


########################################################################
# Function:	show_progressbar
# Description:	Fakes a "progress" bar.
#		You'll see progress every second. If gsm-ussd returns
#		faster than in 20 seconds, the progress bar will be
#		killed. It gsm-ussd times out, the progress bar will 
#		run to 100% and then expire by itself or be killed.
#		Worst case is an expiring progress bar, but gsm-ussd
#		doesn't return for further 10 seconds because the PIN 
#		had to be set...
function show_progressbar {
	local TIMEOUT=20	# This is the default used in gsm-ussd
        local -i COUNT=1

        local DBUS_REF=$(
		kdialog \
		--title "$TITLE" \
		--progressbar "Query running..." \
		$TIMEOUT \
		2>&-
	)

        trap 'qdbus $DBUS_REF close >/dev/null 2>&1; return 0' 0 15

        while (( COUNT <= TIMEOUT )) ; do
                qdbus $DBUS_REF \
			org.freedesktop.DBus.Properties.Set \
			org.kde.kdialog.ProgressDialog value $COUNT \
			>/dev/null 2>&1
                (( COUNT++ ))
                sleep 1
        done

	return 0
}

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
	kdialog \
	--title "$TITLE" \
	--inputbox 'Please enter the USSD query you would like to send:' '*100#' \
	2>&-
)
if [ $? -ne 0 ] ; then
	exit 1
fi

# Ask for PIN, if needed
PIN_OPT=""
if [ $PIN_NEEDED -eq 1 ] ; then
	PIN=$(
		kdialog \
		--title "$TITLE" \
		--password 'Please enter your PIN for your SIM card. If no PIN is needed, leave blank.' \
		2>&-
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
	# kdialog --title "$TITLE" --error "$RESULT"
else
	DIALOG_TYPE="--msgbox"
	# kdialog --title "$TITLE" --msgbox "$RESULT"
fi
kdialog --title "$TITLE" $DIALOG_TYPE "$RESULT"

exit 0
