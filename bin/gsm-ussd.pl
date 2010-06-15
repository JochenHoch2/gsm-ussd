#!/usr/bin/perl
########################################################################
# vim: set expandtab sw=4 ts=4 ai nu: 
########################################################################
# Script:       gsm-ussd
# Description:  Send USSD queries via GSM modem
########################################################################
# Copyright (C) 2010 Jochen Gruse, jochen@zum-quadrat.de
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
# 
########################################################################

use strict;
use warnings;
use sigtrap qw(die normal-signals);
use 5.008;                  # Encode::GSM0338 only vailable since 5.8

use Getopt::Long;
use Pod::Usage;
# use Encode qw(encode decode);
use FindBin;
use lib "$FindBin::RealBin/../lib";

use GSMUSSD::Loggit;
use GSMUSSD::DCS;
use GSMUSSD::Code;
use GSMUSSD::Modem;
use GSMUSSD::UssdQuery;


########################################################################
# Init
########################################################################

our $VERSION            = '0.4.0';          # Our version
my $modemport           = '/dev/ttyUSB1';   # AT port of a Huawei E160 modem
my $timeout_for_answer  = 20;               # Timeout for modem answers in seconds
my @ussd_queries        = ( '*100#' );      # Prepaid account query as default
my $use_cleartext       = undef;            # Need to encode USSD query?
my $cancel_ussd_session = 0;                # User wants to cancel an ongoing USSD session
my $show_online_help    = 0;                # Option flag online help
my $debug               = 0;                # Option flag debug mode
my $expect_logfilename  = undef;            # Filename to log the modem dialog into
my $pin                 = undef;            # Value for option PIN
my @all_args            = @ARGV;            # Backup of args to print them for debug

my $log = GSMUSSD::Loggit->new(0);          # New Logger, logging by default off

# Consts
my $success         =  1;
my $fail            =  0;

my $exit_success    =  0;
my $exit_nopin      =  1;
my $exit_wrongpin   =  2;
my $exit_nonet      =  3;
my $exit_error      =  4;
my $exit_bug        = 10;


# Parse options and react to them
GetOptions (
    'modem|m=s'     =>	\$modemport,
    'timeout|t=i'   =>	\$timeout_for_answer,
    'pin|p=s'       =>	\$pin,
    'cleartext!'    =>  \$use_cleartext,
    'cancel|c'      =>  \$cancel_ussd_session,
    'debug|d'       =>  \$debug,
    'logfile|l=s'   =>	\$expect_logfilename,
    'help|h|?'      =>	\$show_online_help,
) 
or pod2usage(-verbose => 0);

# Online help wanted?
if ( $show_online_help ) {
    pod2usage(-verbose => 1);
}


# Activate our logger
$log->really_log($debug);

# Further arguments are USSD queries
if ( @ARGV != 0 ) {
    @ussd_queries = @ARGV;
}


########################################################################
# Main
########################################################################
$log->DEBUG ("Start, Version $VERSION, Args: ", @all_args);
$log->DEBUG ("Setting output to UTF-8");
binmode (STDOUT, ':utf8');

my $modem = GSMUSSD::Modem->new($modemport, $timeout_for_answer, $expect_logfilename);
if (! $modem->device_accessible() ) {
    print STDERR "ERROR: Modem port \"$modemport\" is not accessible. Possible causes:\n";
    print STDERR "* Modem not plugged in/connected\n";
    print STDERR "* Modem not detected by system\n";
    print STDERR "* Wrong device file given\n";
    print STDERR "* No read/write access to modem\n";
    exit $exit_error;
}

$log->DEBUG ('Opening modem');
if ( ! $modem->open() ) {
    print STDERR 'ERROR: ' . $modem->error(), $/;
    exit $exit_error;
}

if ( ! $modem->probe() ) {
    print STDERR "ERROR: No modem found at device \"$modemport\". Possible causes:\n";
    print STDERR "* Wrong modem device (use -m <dev>)?\n";
    print STDERR "* Modem broken (no reaction to AT)\n";
    exit $exit_error;
}

$modem->echo (1);

if ( $modem->pin_needed() ) {
    $log->DEBUG ("PIN needed");
    if ( ! defined $pin ) {
        print STDERR "ERROR: SIM card is locked, but no PIN to unlock given.\n";
        print STDERR "Use \"-p <pin>\"!\n";
        exit $exit_nopin;
    }
    if ( $modem->enter_pin ($pin) ) {
        $log->DEBUG ("Pin $pin accepted.");
    }
    else {
        print STDERR "ERROR: SIM card is locked, PIN $pin not accepted!\n";
        print STDERR "Start me again with the correct PIN!\n";
        exit $exit_wrongpin;
    }
}

my ( $net_is_available, $reason)  = $modem->get_net_registration_state();
if ( ! $net_is_available ) {
    print STDERR "ERROR: Sorry, no network seems to be available:\n$reason\n";
    exit $exit_nonet;
}

my $ussdquery = GSMUSSD::UssdQuery->new($modem, $use_cleartext);

if ( $cancel_ussd_session ) {
    my $cancel_result = $ussdquery->cancel_ussd_session();
    if ( $cancel_result->{ok} ) {
        print $cancel_result->{msg}, $/;
    }
    else {
        print STDERR $cancel_result->{msg}, $/;
    }
}
else {
    for my $ussd_query ( @ussd_queries ) {
        if ( ! $ussdquery->is_valid_ussd_query ( $ussd_query ) ) {
            print STDERR "WARNING: \"$ussd_query\" is not a valid USSD query - ignored.\n";
            next;
        }
        my $ussd_result = $ussdquery->do_ussd_query ( $ussd_query );
        if ( $ussd_result->{ok} ) {
            if ( $ussdquery->is_in_session() ) {
                print STDERR 'USSD session open, to cancel use "gsm-ussd -c".', $/;
            }
            print $ussd_result->{msg}, $/;
        }
        else {
            print STDERR $ussd_result->{msg}, $/;
        }
    }
}

$log->DEBUG ("Shutting down");
exit $exit_success; # will give control to END


########################################################################
# Subs
########################################################################

########################################################################
# Function: END
# Purpose:  Check for resources in use and free them
# Args:     None
# Returns:  Nothing. Will be called after exit().
END {
    my $exitcode = $?;  # Save it

    my $log = GSMUSSD::Loggit->new($debug);
    $log->DEBUG ("END: Cleaning up");
    if ( defined $modem) {
        $modem->close();
    }
    $? = $exitcode;
}


########################################################################
__END__

=encoding utf-8

=head1 NAME

gsm-ussd

=head1 SYNOPSYS

 gsm-ussd --help|-h|-?
 gsm-ussd [-m <modem>] [-t <timeout>] [-p <pin>] [<ussd-cmd>]
 gsm-ussd [-m <modem>] [-t <timeout>] -c

=head1 OPTIONS AND ARGUMENTS

Please note that this is only a very quick overview.  For further info
about options and USSD queries, please use C<man gsm-ussd>.

=over

=item B<< --modem|-m <modem> >>

Sets the device file to use to connect to the modem. Default is
C</dev/ttyUSB1>.

=item B<< --timeout|-t <timeout_in_secs> >>

The timeout in seconds that the script will wait for an answer after
each command sent to the modem.  Default is B<20> seconds.

=item B<< --pin|-p <PIN> >>

The SIM PIN, if the card is still locked.

=item B<--cleartext>

This option causes gsm-ussd to send USSD queries in cleartext, i.e.
without encoding them into a 7bit-packed-hex-string.

=item B<--no-cleartext>

This is the opposite of the previous option: Use encoding, even if the
modem type does not indicate that it is needed.

=item B<--help|-h|-?>

Shows the online help.

=item B<< --logfile|-l <logfilename> >>

Writes the chat between modem and script into the named log file.

=item B<--debug|-d>

Switches debug mode on. The script will then explain its actions

=item B<--cancel|-c>

Sends a command to cancel any ongoing USSD session. Cancelling 
while no session is active does no harm.

=back

Everything else on the command line is supposed to be a USSD query.
Default is 'B<*100#>'.

=head1 DESCRIPTION

USSD queries are a feature of GSM nets - or better, of their providers. You
might already know one USSD query, if you possess a prepaid SIM card:
B<*100#> This query, typed as a "telephone number" into your mobile phone,
will show the balance of your account. Other codes are available to
replenish your account, query your own phone number and a lot more.

C<gsm-ussd> will let you send USSD queries with your UMTS/GSM modem.

=head1 AUTHOR

Jochen Gruse, L<mailto:jochen@zum-quadrat.de>
