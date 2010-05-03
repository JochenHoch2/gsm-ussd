#!/bin/bash
########################################################################
# Script:	ussd.sh
# Description:	Prototype of a GUI for gsm-ussd
# Author:	Jochen Gruse
# External dependencies:	(Package)
#		grep		(grep)
#		kdialog		(kdebase-bin)
#		qdbus		(libqt4-dbus)
#		zenity		(zenity)
#		gsm-ussd	(gsm-ussd)
########################################################################


########################################################################
# Support functions
########################################################################


########################################################################
# Function:	check_de
# Description:	Tries to divine which Desktop Environment we're running
#		under.
# Output:	"none" if not in X
#		"kde" if running in KDE
#		"gnome" if running in GNOME
#		"unknown" for everything else
function check_de {
	if [ -z "$DISPLAY" ] ; then
		echo none
	elif [ -n "$GNOME_DESKTOP_SESSION_ID" ] ; then
		echo gnome
	elif [ -n "$KDE_FULL_SESSION" ] ; then
		echo kde
	else
		echo unknown
	fi
	return 0
}


########################################################################
# Function:	check_binaries
# Description:	Checks each argument, if a program of that name can
#		be found in the PATH.
# Output:	Available programs are returned.
function check_binaries {
	local AVAILABLE=""

	for BINARY ; do
		if type -f "$BINARY" >/dev/null 2>&1 ; then
			AVAILABLE="$AVAILABLE $BINARY"
		fi
	done
	echo $AVAILABLE
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
# KDE functions
########################################################################


########################################################################
# Function:	get_ussd_query_kde
# Description:	Creates a kdialog text box to enter the USSD query
function get_ussd_query_kde {
	kdialog \
	--title "$TITLE" \
	--inputbox 'Please enter the USSD query you would like to send:' '*100#' \
	2>&-
}


########################################################################
# Function:	get_pin_kde
# Description:	Creates a kdialog text box to enter the PIN
function get_pin_kde {
	kdialog \
	--title "$TITLE" \
	--password 'Please enter your PIN for your SIM card. If no PIN is needed, leave blank.' \
	2>&-
}


########################################################################
# Function:	show_progressbar_kde
# Description:	Fakes a "progress" bar.
#		You'll see progress every second. If gsm-ussd returns
#		faster than in 20 seconds, the progress bar will be
#		killed. It gsm-ussd times out, the progress bar will 
#		run to 100% and then expire by itself or be killed.
#		Worst case is an expiring progress bar, but gsm-ussd
#		doesn't return for further 10 seconds because the PIN 
#		had to be set...
function show_progressbar_kde {
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
# Function:	show_result_kde
# Description:	Creates a kdialog info box to show the USSD query result
function show_result_kde {
	if [ "$1" -ne 0 ] ; then
		local DIALOG_TYPE="--error"
	else
		local DIALOG_TYPE="--msgbox"
	fi
	kdialog --title "$TITLE" $DIALOG_TYPE "$2"
}


########################################################################
# GNOME functions
########################################################################


########################################################################
# Function:	get_ussd_query_gnome
# Description:	Creates a zenity text box to enter the USSD query
function get_ussd_query_gnome {
	zenity \
	--title "$TITLE" \
	--entry \
	--text 'Please enter the USSD query you would like to send:' \
	--entry-text '*100#' \
	2>&-
}


########################################################################
# Function:	get_pin_gnome
# Description:	Creates a zenity text box to enter the PIN
function get_pin_gnome {
	zenity \
	--title "$TITLE" \
	--entry \
	--text 'Please enter your PIN for your SIM card. If no PIN is needed, leave blank.' \
	--hide-text \
	2>&-
}


########################################################################
# Function:	show_progressbar_gnome
# Description:	Fakes a "progress" bar.
function show_progressbar_gnome {

	
        trap 'kill $ZENITY_PID; return 0' 0 2 15

	while : ; do		# Poor man's "yes" B^)
		echo "y"
		sleep 1
	done | \
	zenity \
		--title "$TITLE" \
		--progress \
		--pulsate &
	ZENITY_PID=$!

	wait			# Will not return by itself, must be
				# killed!
	return 0
}


########################################################################
# Function:	show_result_gnome
# Arguments:	$1 - Exit code of gsm-ussd
#		$2 - Message to display
# Description:	Creates a zenity info box to show the USSD query result
function show_result_gnome {
	if [ "$1" -ne 0 ] ; then
		local DIALOG_TYPE="--error"
	else
		local DIALOG_TYPE="--info"
	fi
	zenity --title "$TITLE" $DIALOG_TYPE --text "$(echo "$2" | escape_markup )"
}


########################################################################
# MAIN
########################################################################

# Name of this script, used in dialog titles
TITLE=${0##*/}

# Any options are given over to gsm-ussd. No checking done here!
GSM_USSD_OPTS="$@"

SUPPORTED_DIALOG_TOOLS="kdialog zenity"

# Which DE are we running under?
DESKTOP=$(check_de)
AVAILABLE_DIALOG_TOOLS=$(check_binaries $SUPPORTED_DIALOG_TOOLS)

case $DESKTOP in 
none)	# No X11, use command line program
	exec gsm-ussd $GSM_USSD_OPTS
	# NOTREACHED
	;;
unknown)
	# Something else than GNOME/KDE, find what's available
	if echo "$AVAILABLE_DIALOG_TOOLS" | grep -q kdialog; then
		DESKTOP=kde
	elif echo "$AVAILABLE_DIALOG_TOOLS" | grep -q zenity; then 
		DESKTOP=gnome
	else
		exec gsm-ussd $GSM_USSD_OPTS
		# NOTREACHED
	fi
	;;
esac


# -p/--pin already given? Then we don't have to ask by dialog box
# This is only an approximation, the legal grouping
#	-cdp 1234
# is not recognized
PIN_NEEDED=1
if echo "$GSM_USSD_OPTS" | grep -Eq -- '-p|--pin' ; then
	PIN_NEEDED=0
fi

# Ask for USSD query, set "*100#" as default
USSD_QUERY=$( get_ussd_query_$DESKTOP )
if [ $? -ne 0 ] ; then
	exit 1
fi

# Ask for PIN, if needed
PIN_OPT=""
if [ $PIN_NEEDED -eq 1 ] ; then
	PIN=$( get_pin_$DESKTOP)
	if [ $? -eq 0 -a -n "$PIN" ] ; then
		PIN_OPT="-p $PIN"
	fi
fi

# Start the progress bar display
show_progressbar_$DESKTOP &
PROGRESS_PID=$!

# Do the actual work
RESULT=$( gsm-ussd $PIN_OPT $GSM_USSD_OPTS "$USSD_QUERY" 2>&1 )
GSM_USSD_EXITCODE=$?

# End progress bar display (if not already gone)
kill $PROGRESS_PID >&- 2>&-

# Show gsm-ussd result in appropiate dialog box
show_result_$DESKTOP "$GSM_USSD_EXITCODE" "$RESULT"

exit 0
