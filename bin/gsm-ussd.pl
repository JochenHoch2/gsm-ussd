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
use Encode qw(encode decode);
use FindBin;
use lib "$FindBin::RealBin/../lib";

use GSMUSSD::Loggit;
use GSMUSSD::DCS;
use GSMUSSD::Code;
use GSMUSSD::Modem;

# use Expect;     # External dependency


########################################################################
# Init
########################################################################

our $VERSION            = '0.3.9';          # Our version
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

# This is a list of modems that need the PDU format for query
# As of now, these are all Huaweis...
my @pdu_modems = (
    'E160',
    'E165G',
    'E1550',
);


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
    print STDERR 'Error: ' . $modem->error(), $/;
    exit $exit_error;
}

if ( ! $modem->probe() ) {
    print STDERR "No modem found at device \"$modemport\". Possible causes:\n";
    print STDERR "* Wrong modem device (use -m <dev>)?\n";
    print STDERR "* Modem broken (no reaction to AT)\n";
    exit $exit_error;
}

$modem->echo (1);

my $modem_model = $modem->model();

if ( ! defined $use_cleartext ) {
    if ( modem_needs_pdu_format ( $modem_model ) ) {
        $log->DEBUG ("Modem type \"$modem_model\" needs PDU format for USSD query.");
        $use_cleartext = 0;
    }
    else {
        $log->DEBUG ("Modem type \"$modem_model\" needs cleartext for USSD query.");
        $use_cleartext = 1;
    }
}
else {
    DEBUG( 'Will use cleartext as given on the command line: ', $use_cleartext );
}

if ( $modem->pin_needed() ) {
    $log->DEBUG ("PIN needed");
    if ( ! defined $pin ) {
        print STDERR "SIM card is locked, but no PIN to unlock given.\n";
        print STDERR "Use \"-p <pin>\"!\n";
        exit $exit_nopin;
    }
    if ( $modem->enter_pin ($pin) ) {
        $log->DEBUG ("Pin $pin accepted.");
    }
    else {
        print STDERR "SIM card is locked, PIN $pin not accepted!\n";
        print STDERR "Start me again with the correct PIN!\n";
        exit $exit_wrongpin;
    }
}

my ( $net_is_available, $reason)  = $modem->get_net_registration_state();
if ( ! $net_is_available ) {
    print STDERR "Sorry, no network seems to be available:\n$reason\n";
    exit $exit_nonet;
}

if ( $cancel_ussd_session ) {
    my $cancel_result = cancel_ussd_session();
    if ( $cancel_result->{ok} ) {
        print $cancel_result->{msg}, $/;
    }
    else {
        print STDERR $cancel_result->{msg}, $/;
    }
}
else {
    for my $ussd_query ( @ussd_queries ) {
        if ( ! is_valid_ussd_query ( $ussd_query ) ) {
            print STDERR "\"$ussd_query\" is not a valid USSD query - ignored.\n";
            next;
        }
        my $ussd_result = do_ussd_query ( $ussd_query );
        if ( $ussd_result->{ok} ) {
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
# Function: modem_needs_pdu_format
# Args:     $model - The model type reported by the modem
# Returns:  0   -   Modem type needs cleartext USSD query
#           1   -   Modem type needs PDU format
sub modem_needs_pdu_format {
    my ($model) = @_;

    foreach my $modem (@pdu_modems) {
        if ( $model eq $modem ) {
            return 1;
        }
    }
    return 0;
}


########################################################################
# Function: is_valid_ussd_query
# Args:     $query - The USSD query to check
# Returns:  0   -   Query contains illegal characters
#           1   -   Query is legal
sub is_valid_ussd_query {
    my ( $query ) = @_;

    # The first RA checks for a standard USSD
    # The second allows simple numbers as used by USSD sessions
    if ( $query =~ m/^\*[0-9*]+#$/ || $query =~ m/^\d+$/) {
        return $success;
    }
    return $fail;
}


########################################################################
# Function: do_ussd_query
# Args:     $query      The USSD query to send ('*100#')
# Returns:  Hashref 
#           Key 'ok':   $success if USSD query successfully transmitted
#                       and answer received
#                       $fail if USSD query aborted or not able to send
#           Key 'msg':  Error message or USSD query result, in accordance
#                       to the value of 'ok'.
sub do_ussd_query {
    my ( $query ) = @_;

    $log->DEBUG ("Starting USSD query \"$query\"");

    my $result = $modem->send_command (
        ussd_query_cmd($query, $use_cleartext),
        'wait_for_cmd_answer',
    );

    if ( $result->{ok} ) {
        $log->DEBUG ("USSD query successful, answer received");
        my ($response_type,$response,$encoding)
            = $result->{description}
            =~ m/
                (\d+)           # Response type
                (?:
                    ,"([^"]+)"  # Response
                    (?:
                        ,(\d+)  # Encoding
                    )?          # ... may be missing or ...
                )?              # ... Response *and* Encoding may be missing
            /ix;

        if ( ! defined $response_type ) {
            # Didn't the RE match?
            $log->DEBUG ("Can't parse CUSD message: \"", $result->{description}, "\"");
            return {
                ok  => $fail,
                msg =>  "Can't understand modem answer: \""
                        . $result->{description} . "\"",
            };
        }
        elsif ( $response_type == 0 ) {
            $log->DEBUG ("USSD response type: No further action required (0)");
        }
        elsif ( $response_type == 1 ) {
            $log->DEBUG ("USSD response type: Further action required (1)");
            print STDERR "USSD session open, to cancel use \"gsm-ussd -c\".\n";
        }
        elsif ( $response_type == 2 ) {
            my $msg = "USSD response type: USSD terminated by network (2)";
            $log->DEBUG ($msg);
            return { ok => $fail, msg => $msg };
        }
        elsif ( $response_type == 3 ) {
            my $msg = ("USSD response type: Other local client has responded (3)");
            $log->DEBUG ($msg);
            return { ok => $fail, msg => $msg };
        }
        elsif ( $response_type == 4 ) {
            my $msg = ("USSD response type: Operation not supported (4)");
            $log->DEBUG ($msg);
            return { ok => $fail, msg => $msg };
        }
        elsif ( $response_type == 5 ) {
            my $msg = "USSD response type: Network timeout (5)";
            $log->DEBUG ($msg);
            return { ok => $fail, msg => $msg };
        }
        else {
            my $msg = "CUSD message has unknown response type \"$response_type\"";
            $log->DEBUG ($msg);
            return { ok => $fail, msg => $msg };
        }
        # Only reached if USSD response type is 0 or 1
        return { ok => $success, msg => interpret_ussd_data ($response, $encoding) };
    }
    else {
        $log->DEBUG ("USSD query failed, error: " . $result->{description});
        return { ok => $fail, msg => $result->{description} };
    }
}


########################################################################
# Function: cancel_ussd_session
# Args:     None.
# Returns:  Hashref 
#           Key 'ok':   $success if USSD query successfully transmitted
#                       and answer received
#                       $fail if USSD query aborted or not able to send
#           Key 'msg':  Error message or USSD query result, in accordance
#                       to the value of 'ok'.
sub cancel_ussd_session {

    $log->DEBUG ('Trying to cancel USSD session');
    my $result = $modem->send_command ( "AT+CUSD=2\r", 'wait_for_OK' );
    if ( $result->{ok} ) {
        my $msg = 'USSD cancel request successful';
        $log->DEBUG ($msg);
        return { ok => $success, msg => $msg };
    }
    else {
        my $msg = 'No USSD session to cancel.';
        $log->DEBUG ($msg);
        return { ok => $fail, msg => $msg };
    }
}


########################################################################
# Function: interpret_ussd_data
# Args:     $response   -   The USSD string response
#           $encoding   -   The USSD encoding (dcs)
# Returns:  String containint the USSD response in clear text
sub interpret_ussd_data {
    my ($response, $encoding) = @_;

    if ( ! defined $encoding ) {
        $log->DEBUG ("CUSD message has no encoding, interpreting as cleartext");
        return $response;
    }
    my $dcs = GSMUSSD::DCS->new($encoding);
    my $code= GSMUSSD::Code->new();

    if ( $dcs->is_default_alphabet() ) {
        $log->DEBUG ("Encoding \"$encoding\" says response is in default alphabet");
        if ( $use_cleartext ) {
            $log->DEBUG ("Modem uses cleartext, interpreting message as cleartext");
            return $response;
        }
        elsif ( $encoding == 0 ) {
            return $code->decode_8bit( $response );
        }
        elsif ( $encoding == 15 ) {
            return decode( 'gsm0338', $code->decode_7bit( $response ) );
        }
        else {
            $log->DEBUG ("CUSD message has unknown encoding \"$encoding\", using 0");
            return $code->decode_8bit( $response );
        }
        # NOTREACHED
    }
    elsif ( $dcs->is_ucs2() ) {
        $log->DEBUG ("Encoding \"$encoding\" says response is in UCS2-BE");
        return decode ('UCS-2BE', $code->decode_8bit ($response));
    }
    elsif ( $dcs->is_8bit() ) {
        $log->DEBUG ("Encoding \"$encoding\" says response is in 8bit");
        return $code->decode_8bit ($response);
    }
    else {
        $log->DEBUG ("CUSD message has unknown encoding \"$encoding\", using 0");
        return $code->decode_8bit( $response );
    }
    # NOTREACHED
}


########################################################################
# Function: ussd_query_cmd
# Args:     The USSD-Query to send 
# Returns:  An AT+CUSD command with properly encoded args
sub ussd_query_cmd {
	my ($ussd_cmd)                  = @_;
	my $result_code_presentation    = '1';      # Enable result code presentation
	my $encoding                    = '15';     # Default alphabet, 7bit
	my $ussd_string;

    if ( $use_cleartext ) {
        $ussd_string = $ussd_cmd;
    }
    else {
        my $code = GSMUSSD::Code->new();
        $ussd_string = $code->encode_7bit( encode('gsm0338', $ussd_cmd) );
    }
	return sprintf 'AT+CUSD=%s,"%s",%s', $result_code_presentation, $ussd_string, $encoding;
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
