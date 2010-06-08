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
use Encode  qw(encode decode);
use FindBin;
use lib "$FindBin::RealBin/../lib";

use GSMUSSD::Loggit;
use GSMUSSD::DCS;
use GSMUSSD::Stty;
use GSMUSSD::Lockfile;
use GSMUSSD::Code;
use GSMUSSD::NetworkErrors;

use Expect;     # External dependency


########################################################################
# Init
########################################################################

our $VERSION            = '0.3.9';          # Our version
my $modemport           = '/dev/ttyUSB1';   # AT port of a Huawei E160 modem
# my $modem_lockfile      = undef;            # The modem lockfile (e.g. /var/run/LCK..ttyUSB1)
my $modem_fh            = undef;
my $timeout_for_answer  = 20;               # Timeout for modem answers in seconds
my @ussd_queries        = ( '*100#' );      # Prepaid account query as default
my $use_cleartext       = undef;            # Need to encode USSD query?
my $cancel_ussd_session = 0;                # User wants to cancel an ongoing USSD session
my $show_online_help    = 0;                # Option flag online help
my $debug               = 0;                # Option flag debug mode
my $expect              = undef;            # The Expect object
my $expect_logfilename  = undef;            # Filename to log the modem dialog into
my $pin                 = undef;            # Value for option PIN
my @all_args            = @ARGV;            # Backup of args to print them for debug

my $num_net_reg_retries = 10;               # Number of retries if modem is not already
                                            # registered in a net

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

# The Expect programs differ in the way they react to modem answers
my %expect_programs = (
    # wait_for_OK:  The modem will react with OK/ERROR/+CM[SE] ERROR
    #               This in itself will be the result, further information
    #               might be available between AT... and OK.
    wait_for_OK =>  [
        # Ignore status messages
        [ qr/\r\n([\+\^](?:BOOT|DSFLOWRPT|MODE|RSSI|SIMST|SRVST)):[ ]*([^\r\n]*)\r\n/i
            => \&ignore_state_line
        ],
        # Identify +CREG status message
        # (+CREG modem answer has got two arguments "\d,\d"!)
        [ qr/\r\n(\+CREG):[ ]*(\d)\r\n/i
            => \&ignore_state_line
        ],
        # Fail states of the modem (network lost, SIM problems, ...)
        [ qr/\r\n(\+CM[SE] ERROR):[ ]*([^\r\n]*)\r\n/i
            => \&network_error
        ],
        # AT command (TTY echo of input)
        [ qr/^AT([^\r\n]*)\r/i
            =>  sub {
                    my $exp = shift;
                    $log->DEBUG("AT found, -> ",$exp->match() );
                    exp_continue_timeout;
                }
        ],
        # Modem answers to command
        [ qr/\r\n(OK|ERROR)\r\n/i
            =>  sub {
                    my $exp = shift;
                    $log->DEBUG ("OK/ERROR found: ", ($exp->matchlist())[0] );
                }
        ],
    ],
    # wait_for_cmd_answer:
    #               The command answers with OK/ERROR, but the real
    #               result will arrive later out of the net
    wait_for_cmd_answer =>  [
        # Ignore status messages
        [ qr/\r\n(\^(?:BOOT|DSFLOWRPT|MODE|RSSI|SIMST|SRVST)):[ ]*([^\r\n]*)\r\n/i
            => \&ignore_state_line
        ],
        # Identify +CREG status message
        # (+CREG modem answer has got two arguments "\d+, \d+"!)
        [ qr/\r\n(\+CREG):[ ]*(\d)\r\n/i
            => \&ignore_state_line
        ],
        # Fail states of the modem (network lost, SIM problems, ...)
        [ qr/\r\n(\+CM[SE] ERROR):[ ]*([^\r\n]*)\r\n/i
            =>  \&network_error
        ],
        # The expected result - all state messages have already been
        # dealt with. Everything that reaches this part has to be the
        # result of the sent command.
        # Some more checks of that?
        [ qr/\r\n(\+[^:]+):[ ]*([^\r\n]*)\r\n/i
            => sub {
                my $exp = shift;
                my $match = $exp->match();
                $match =~ s/(?:^\s+|\s+$)//g;
                $log->DEBUG ("Expected answer: ", $match);
            }
        ],
        # AT command (TTY echo of input)
        [ qr/^AT([^\r\n]*)\r/i
            =>  sub {
                    my $exp = shift;
                    $log->DEBUG("AT found, -> ",$exp->match() );
                    exp_continue_timeout;
                }
        ],
        # OK means that the query was successfully sent into the
        # net. Carry on!
        [ qr/\r\n(OK)\r\n/i
            =>  sub {
                    $log->DEBUG ("OK found, continue waiting for result"); 
                    exp_continue;
                }
        ],
        # ERROR means that the command wasn't syntactically correct
        # oder couldn't be understood (wrong encoding?). Stop here,
        # as no more meaningful results can be expected.
        [ qr/\r\n(ERROR)\r\n/i
            =>  sub {
                    $log->DEBUG ("ERROR found, aborting"); 
                }
        ],
    ],
);


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

check_modemport ($modemport);

my $lockfile = GSMUSSD::Lockfile->new ($modemport);

if ( ! $lockfile->lock() ) {
    print STDERR "Can't get lock file for $modemport!\n";
    print STDERR "* Wrong modem device? (use -m <dev>)?\n";
    print STDERR "* Stale lock file for $modemport in /var/lock?\n";
    exit $exit_error;
}

$log->DEBUG ("Opening modem");
if ( ! open $modem_fh, '+<:raw', $modemport ) {
    print STDERR "Modem port \"$modemport\" seems in order, but cannot open it anyway:\n$!\n";
    exit $exit_error;
}

my $stty = GSMUSSD::Stty->new($modem_fh)->save()->set_raw_noecho();

$log->DEBUG ("Initialising Expect");
$expect	= Expect->exp_init($modem_fh);
if (defined $expect_logfilename) {
    $expect->log_file($expect_logfilename, 'w');
}

if ( ! check_for_modem() ) {
    print STDERR "No modem found at device \"$modemport\". Possible causes:\n";
    print STDERR "* Wrong modem device (use -m <dev>)?\n";
    print STDERR "* Modem broken (no reaction to AT)\n";
    exit $exit_error;
}

set_modem_echo (1);

my $modem_model = get_modem_model();
if ( ! defined $modem_model ) {
    $modem_model = '';
}

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

if ( pin_needed() ) {
    $log->DEBUG ("PIN needed");
    if ( ! defined $pin ) {
        print STDERR "SIM card is locked, but no PIN to unlock given.\n";
        print STDERR "Use \"-p <pin>\"!\n";
        exit $exit_nopin;
    }
    if ( enter_pin ($pin) ) {
        $log->DEBUG ("Pin $pin accepted.");
    }
    else {
        print STDERR "SIM card is locked, PIN $pin not accepted!\n";
        print STDERR "Start me again with the correct PIN!\n";
        exit $exit_wrongpin;
    }
}

my ( $net_is_available, $reason)  = get_net_registration_state ( $num_net_reg_retries );
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
    my $log = GSMUSSD::Loggit->new($debug);
    $log->DEBUG ("END: Cleaning up");
    my $exitcode = $?;  # Save it
    if ( defined $modem_fh) {
        if ( defined $stty ) {
            $log->DEBUG ("END: Resetting serial interface");
            $stty->restore();
        }
        $log->DEBUG ("END: Closing modem interface");
        close $modem_fh;
    }
    if ( defined ($lockfile) && $lockfile->is_locked() ) {
        $log->DEBUG ("END: Removing lock file");
        $lockfile = undef;
    }
    $? = $exitcode;
}


########################################################################
# Function: check_modemport
# Args:     File to check as modem port
# Returns:  void, exits if modem port check fails
sub check_modemport {
    my ($mp) = @_;

    if ( ! -e $mp ) {
        print STDERR "Modem port \"$mp\" doesn't exist. Possible causes:\n";
        print STDERR "* Modem not plugged in/connected\n";
        print STDERR "* Modem broken\n";
        print STDERR "Perhaps use another device with -m?\n";
        exit $exit_error;
    }

    if ( ! -c $mp ) {
        print STDERR "Modem device \"$mp\" is no character device file. Possible causes:\n";
        print STDERR "* Wrong device file given (-m ?)\n";
        print STDERR "* Device file broken?\n";
        print STDERR "Please check!\n";
        exit $exit_error;
    }

    if ( ! -r $mp ) {
        print STDERR "Can't read from device \"$mp\".\n";
        print STDERR "Set correct rights for \"$mp\" with chmod?\n";
        print STDERR "Perhaps use another device with -m?\n";
        exit $exit_error;
    }

    if ( ! -w $mp ) {
        print STDERR "Can't write to device \"$mp\".\n";
        print STDERR "Set correct rights for \"$mp\" with chmod?\n";
        print STDERR "Perhaps use another device with -m?\n";
        exit $exit_error;
    }
}


########################################################################
# Function: check_for_modem
# Args:     None
# Returns:  0   No modem found 
#           1   Modem found
#
# "Finding a modem" is hereby defined as getting a reaction of "OK"
# to writing "AT" into the file handle in question.
sub check_for_modem {

    $log->DEBUG ("Starting modem check (AT)");
    my $result = send_command ( "AT", 'wait_for_OK' );
    if ( $result->{ok} ) {
        $log->DEBUG ("Modem found (AT->OK)");
        return 1;
    }
    else {
        $log->DEBUG ("No modem found, error: $result->{description}");
        return 0;
    }
}


########################################################################
# Function: set_modem_echo
# Args:     true    -   Echo on
#           false   -   Echo off
# Returns:  0   -   Success
#           1   -   Fail 
sub set_modem_echo {
    my ($echo_on) = @_;
    my $modem_echo_command = '';

    if ($echo_on) {
        $modem_echo_command = 'ATE1';
        $log->DEBUG ("Enabling modem echo ($modem_echo_command)");
    }
    else {
        $modem_echo_command = 'ATE0';
        $log->DEBUG ("Disabling modem echo ($modem_echo_command)");
    }

    my $result = send_command ( $modem_echo_command, 'wait_for_OK' );
    if ( $result->{ok} ) { 
        $log->DEBUG ("$modem_echo_command successful");
        return 1;
    }   
    else {
        $log->DEBUG ("$modem_echo_command failed, error: $result->{description}");
        return 0;
    }   
}


########################################################################
# Function: get_modem_model
# Args:     None
# Returns:  String  Name of the modem model
#           undef   No name found
#
# Different modems report *very* different things here, but it's enough
# to see if it's a E160-type modem.
sub get_modem_model {

    $log->DEBUG ("Querying modem type");
    my $result = send_command ( "AT+CGMM", 'wait_for_OK' );
    if ( $result->{ok} ) {
        $log->DEBUG ("Modem type found: ", $result->{description} );
        return $result->{description};
    }
    else {
        $log->DEBUG ("No modem type found: ", $result->{description});
        return undef;
    }
}


########################################################################
# Function: pin_needed
# Args:     None.
# Returns:  0   No PIN needed, SIM card is unlocked
#           1   PIN (or PUK) still needed, SIM card still locked
sub pin_needed {

    $log->DEBUG ("Starting SIM state query (AT+CPIN?)");
    my $result = send_command ( 'AT+CPIN?', 'wait_for_OK' );
    if ( $result->{ok} ) {
        $log->DEBUG ("Got answer for SIM state query");
        if ( $result->{match} eq 'OK') {
            if ( $result->{description} =~ m/READY/ ) {
                $log->DEBUG ("SIM card is unlocked");
                return 0;
            }
            elsif ( $result->{description} =~ m/SIM PIN/ ) {
                $log->DEBUG ("SIM card is locked");
                return 1;
            }
            else {
                $log->DEBUG ("Couldn't parse SIM state query result: " . $result->{description});
                return 1;
            }
        }
        else {
            $log->DEBUG ("SIM card locked - failed query? -> " . $result->{match} );
            return 1;
        }
    }
    else {
        $log->DEBUG (" SIM state query failed, error: " . $result->{description} );
        return 1;
    }
}


########################################################################
# Function: enter_pin
# Args:     The PIN to unlock the SIM card
# Returns:  0   Unlocking the SIM card failed
#           1   SIM is now unlocked
sub enter_pin {
    my ($pin) = @_;

    $log->DEBUG ("Unlocking SIM using PIN $pin");
    my $result = send_command ( "AT+CPIN=$pin", 'wait_for_OK' );
    if ( $result->{ok} ) {
        $log->DEBUG ("SIM card unlocked: ", $result->{match} );
        return 1;
    }
    else {
        $log->DEBUG ("SIM card still locked, error: ", $result->{description});
        return 0;
    }
}


########################################################################
# Function: get_net_registration_state
# Args:     $max_tries - Number of tries 
# Returns:  0 - No net available
#           1 - Modem is registered in a net
sub get_net_registration_state {
    my ($max_tries)                     = @_;
    my $num_tries                       = 1;
    my $wait_time_between_net_checks    = 3;
    my $last_state_message              = '';

    $log->DEBUG ("Waiting for net registration, max $max_tries tries");
    while ($num_tries <= $max_tries) {
        $log->DEBUG ("Try: $num_tries");
        my $result = send_command ( 'AT+CREG?', 'wait_for_OK' );
        if ( $result->{ok} ) {
            $log->DEBUG ('Net registration query result received, parsing');
            my ($n, $stat) = $result->{description} =~ m/\+CREG:\s+(\d),(\d)/i;
            if ( ! defined $n || ! defined $stat) {
                $last_state_message = 'Cannot parse +CREG answer: ' . $result->{description}; 
                $log->DEBUG ( $last_state_message );
                return ( 0, $last_state_message );
            }
            if ( $stat == 0 ) {
                $last_state_message = 'Not registered, MT not searching a new operator to register to';
                $log->DEBUG ( $last_state_message );
                return ( 0, $last_state_message );
            }
            elsif ( $stat == 1 ) {
                $last_state_message = 'Registered, home network';
                $log->DEBUG ( $last_state_message );
                if ( $num_tries != 1 ) {
                    $log->DEBUG ( 'Sleeping one more time for settling in');
                    sleep $wait_time_between_net_checks;
                }
                return ( 1, $last_state_message );
            }
            elsif ( $stat == 2 ) {
                $last_state_message = 'Not registered, currently searching new operator to register to';
                $log->DEBUG ( $last_state_message );
            }
            elsif ( $stat == 3) {
                $last_state_message = 'Registration denied'; 
                $log->DEBUG ( $last_state_message );
                return ( 0, $last_state_message );
            }
            elsif ( $stat == 4) {
                $last_state_message = 'Registration state unknown';
                $log->DEBUG ( $last_state_message );
            }
            elsif ( $stat == 5 ) {
                $last_state_message = 'Registered, roaming';
                $log->DEBUG ( $last_state_message );
                if ( $num_tries != 1 ) {
                    $log->DEBUG ( 'Sleeping one more time for settling in');
                    sleep $wait_time_between_net_checks;
                }
                return ( 1, $last_state_message );
            }
            else {
                $last_state_message = "Cannot understand net reg state code $stat";
                $log->DEBUG ( $last_state_message );
            }
        }
        else {
            $last_state_message = 'Querying net registration failed, error: ' . $result->{description}; 
            $log->DEBUG ( $last_state_message );
            return ( 0, $last_state_message );
        }
        $log->DEBUG ("Sleeping for $wait_time_between_net_checks seconds");
        sleep $wait_time_between_net_checks;
        ++ $num_tries;
    }
    return ( 0, "No net registration in $max_tries tries found, last result:\n$last_state_message" );
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

    my $result = send_command (
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
    my $result = send_command ( "AT+CUSD=2\r", 'wait_for_OK' );
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
# Function: send_command
# Args:     $cmd        String holding the command to send (usually 
#                       something like "AT...")
#           $how_to_react
#                       String explaining which Expect program to use:
#                       wait_for_OK
#                           return immediately in case of OK/ERROR
#                       wait_for_cmd_answer
#                           Break in case of ERROR, but wait for 
#                           the real result after OK
# Returns:  Hashref    Result of sent command
#           Key 'ok':   $success if AT command successfully transmitted
#                       and answer received
#                       $fail if AT command aborted or not able to send
#           Key 'match':
#                       What expect matched,
#                       'OK'|'ERROR'|'+CME ERROR'|'+CMS ERROR'
#           Key 'description':
#                       Error description, OK/ERROR, output of modem
#                       between AT command and OK, result of USSD query
#                       after OK, all in accordance to key 'ok' and
#                       arg $how_to_react
sub send_command {
    my ($cmd, $how_to_react)	= @_;

    if ( ! exists $expect_programs{$how_to_react} ) {
        print STDERR "This should not have happened - ";
        print STDERR "unknown expect program \"$how_to_react\" wanted!\n";
        print STDERR "This is a bug, please report!\n";
        exit $exit_bug;
    }

    $log->DEBUG ("Sending command: $cmd");
    $expect->send("$cmd\015");

    my (
        $matched_pattern_pos,
        $error,
        $match_string,
        $before_match,
        $after_match
    ) =
    $expect->expect (
            $timeout_for_answer,
            @{$expect_programs{$how_to_react}},
        );

    if ( !defined $error ) {
        my ($first_word, $args ) = $expect->matchlist();
        $first_word = uc $first_word;
        $match_string =~ s/(?:^\s+|\s+$)//g;    # crop whitespace
        if ( $first_word eq 'ERROR' ) {
            # OK/ERROR are two of the three "command done" markers.
            return {
                ok          => $fail,
                match       => $match_string,
                description => 'Broken command',
            };
        }
        elsif ( $first_word eq '+CMS ERROR' ) {
            # After this error there will be no OK/ERROR anymore
            my $errormessage = GSMUSSD::NetworkErrors->new()->get_cms_error($args);
            return {
                ok          => $fail,
                match       => $match_string,
                description => "GSM network error: $errormessage ($args)",
            };
        }
        elsif ( $first_word eq '+CME ERROR' ) {
            # After this error there will be no OK/ERROR anymore
            my $errormessage = GSMUSSD::NetworkErrors->new()->get_cme_error($args);
            return {
                ok          => $fail,
                match       => $match_string,
                description => "GSM equipment error: $errormessage ($args)",
            };
        }
        elsif ( $first_word eq 'OK' ) {
            # $before_match contains data between AT and OK
            $before_match =~ s/(?:^\s+|\s+$)//g;    # crop whitespace
            return {
                ok          => $success,
                match       => $match_string,
                description => $before_match,
            };
        }
        elsif ( $first_word =~ /^[\^\+]/ ) {
            return {
                ok          => $success,
                match       => $match_string,
                description => $match_string,
            };
        }
        else {
            return {
                ok          => $fail,
                match       => $match_string,
                description => "PANIC! Can't parse Expect result: \"$match_string\"",
            } ;
        }
    }
    else {
        # Report Expect error and bail
        if ($error =~ /^1:/) {
            # Timeout
            return {
                ok => $fail,
                match => $error,
                description => "No answer for $timeout_for_answer seconds!",
            };
        }
        elsif ($error =~ /^2:/) {
            # EOF
            return {
                ok          => $fail,
                match       => $error,
                description => "EOF from modem received - modem unplugged?",
            };
        }
        elsif ($error =~ /^3:/) {
            # Spawn id died
            return {
                ok          => $fail,
                match       => $error,
                description => "PANIC! Can't happen - spawn ID died!",
            };
        }
        elsif ($error =~ /^4:/) {
            # Read error
            return {
                ok          => $fail,
                match       => $error,
                description => "Read error accessing modem: $!",
            };
        }
        else {
            return {
                ok          => $fail,
                match       => $error,
                description => "PANIC! Can't happen - unknown Expect error \"$error\"",
            };
        }
    }
    return {
        ok          => $fail,
        match       => '',
        description => "PANIC! Can't happen - left send_command() unexpectedly!",
    };
}


########################################################################
# Function: ignore_state_line
# Args:     $exp        The Expect object in use
# Returns:  Nothing, but continues the expect() call
sub ignore_state_line {
    my $exp = shift;
    my ($state_name, $result) = $exp->matchlist();

    $log->DEBUG("$state_name: $result, ignored");
    exp_continue_timeout;
}


########################################################################
# Function: network_error
# Args:     $exp        The Expect object in use
#           $state_msg_result  Value of state message
# Returns:  Nothing, will end the expect() call
sub network_error {
    my $exp = shift;
    my ($error_msg_type,$error_msg_value) = $exp->matchlist();

    $log->DEBUG ("Network error $error_msg_type with data \"$error_msg_value\" detected.");
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
