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
use 5.008;                  # Encode::GSM0338 only vailable since 5.8

use Getopt::Long;
use Pod::Usage;
use Encode  qw(encode decode);
use POSIX   qw(:termios_h);
use Fcntl;

use Expect;     # External dependency


########################################################################
# Init
########################################################################

our $VERSION            = '0.3.3';          # Our version
my $modemport           = '/dev/ttyUSB1';   # AT port of a Huawei E160 modem
my $modem_lockfile      = undef;            # The modem lockfile (e.g. /var/run/LCK..ttyUSB1)
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

# Further arguments are USSD queries
if ( @ARGV != 0 ) {
    @ussd_queries = @ARGV;
}

# Set up signal handler for INT and TERM
$SIG{'INT'}     = \&clean_exit;
$SIG{'TERM'}    = \&clean_exit;

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
                    DEBUG("AT found, -> ",$exp->match() );
                    exp_continue_timeout;
                }
        ],
        # Modem answers to command
        [ qr/\r\n(OK|ERROR)\r\n/i
            =>  sub {
                    my $exp = shift;
                    DEBUG ("OK/ERROR found: ", ($exp->matchlist())[0] );
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
                DEBUG ("Expected answer: ", $match);
            }
        ],
        # AT command (TTY echo of input)
        [ qr/^AT([^\r\n]*)\r/i
            =>  sub {
                    my $exp = shift;
                    DEBUG("AT found, -> ",$exp->match() );
                    exp_continue_timeout;
                }
        ],
        # OK means that the query was successfully sent into the
        # net. Carry on!
        [ qr/\r\n(OK)\r\n/i
            =>  sub {
                    DEBUG ("OK found, continue waiting for result"); 
                    exp_continue;
                }
        ],
        # ERROR means that the command wasn't syntactically correct
        # oder couldn't be understood (wrong encoding?). Stop here,
        # as no more meaningful results can be expected.
        [ qr/\r\n(ERROR)\r\n/i
            =>  sub {
                    DEBUG ("ERROR found, aborting"); 
                }
        ],
    ],
);

my %gsm_error = (
    # CMS ERRORs are network related errors
    '+CMS ERROR' => {
          '1' => 'Unassigned number',
          '8' => 'Operator determined barring',
         '10' => 'Call bared',
         '21' => 'Short message transfer rejected',
         '27' => 'Destination out of service',
         '28' => 'Unindentified subscriber',
         '29' => 'Facility rejected',
         '30' => 'Unknown subscriber',
         '38' => 'Network out of order',
         '41' => 'Temporary failure',
         '42' => 'Congestion',
         '47' => 'Recources unavailable',
         '50' => 'Requested facility not subscribed',
         '69' => 'Requested facility not implemented',
         '81' => 'Invalid short message transfer reference value',
         '95' => 'Invalid message unspecified',
         '96' => 'Invalid mandatory information',
         '97' => 'Message type non existent or not implemented',
         '98' => 'Message not compatible with short message protocol',
         '99' => 'Information element non-existent or not implemente',
        '111' => 'Protocol error, unspecified',
        '127' => 'Internetworking , unspecified',
        '128' => 'Telematic internetworking not supported',
        '129' => 'Short message type 0 not supported',
        '130' => 'Cannot replace short message',
        '143' => 'Unspecified TP-PID error',
        '144' => 'Data code scheme not supported',
        '145' => 'Message class not supported',
        '159' => 'Unspecified TP-DCS error',
        '160' => 'Command cannot be actioned',
        '161' => 'Command unsupported',
        '175' => 'Unspecified TP-Command error',
        '176' => 'TPDU not supported',
        '192' => 'SC busy',
        '193' => 'No SC subscription',
        '194' => 'SC System failure',
        '195' => 'Invalid SME address',
        '196' => 'Destination SME barred',
        '197' => 'SM Rejected-Duplicate SM',
        '198' => 'TP-VPF not supported',
        '199' => 'TP-VP not supported',
        '208' => 'D0 SIM SMS Storage full',
        '209' => 'No SMS Storage capability in SIM',
        '210' => 'Error in MS',
        '211' => 'Memory capacity exceeded',
        '212' => 'Sim application toolkit busy',
        '213' => 'SIM data download error',
        '255' => 'Unspecified error cause',
        '300' => 'ME Failure',
        '301' => 'SMS service of ME reserved',
        '302' => 'Operation not allowed',
        '303' => 'Operation not supported',
        '304' => 'Invalid PDU mode parameter',
        '305' => 'Invalid Text mode parameter',
        '310' => 'SIM not inserted',
        '311' => 'SIM PIN required',
        '312' => 'PH-SIM PIN required',
        '313' => 'SIM failure',
        '314' => 'SIM busy',
        '315' => 'SIM wrong',
        '316' => 'SIM PUK required',
        '317' => 'SIM PIN2 required',
        '318' => 'SIM PUK2 required',
        '320' => 'Memory failure',
        '321' => 'Invalid memory index',
        '322' => 'Memory full',
        '330' => 'SMSC address unknown',
        '331' => 'No network service',
        '332' => 'Network timeout',
        '340' => 'No +CNMA expected',
        '500' => 'Unknown error',
        '512' => 'User abort',
        '513' => 'Unable to store',
        '514' => 'Invalid Status',
        '515' => 'Device busy or Invalid Character in string',
        '516' => 'Invalid length',
        '517' => 'Invalid character in PDU',
        '518' => 'Invalid parameter',
        '519' => 'Invalid length or character',
        '520' => 'Invalid character in text',
        '521' => 'Timer expired',
        '522' => 'Operation temporary not allowed',
        '532' => 'SIM not ready',
        '534' => 'Cell Broadcast error unknown',
        '535' => 'Protocol stack busy',
        '538' => 'Invalid parameter',
    },
    # CME ERRORs are equipment related errors (missing SIM etc.)
    '+CME ERROR' => {
              '0' => 'Phone failure',
              '1' => 'No connection to phone',
              '2' => 'Phone adapter link reserved',
              '3' => 'Operation not allowed',
              '4' => 'Operation not supported',
              '5' => 'PH_SIM PIN required',
              '6' => 'PH_FSIM PIN required',
              '7' => 'PH_FSIM PUK required',
             '10' => 'SIM not inserted',
             '11' => 'SIM PIN required',
             '12' => 'SIM PUK required',
             '13' => 'SIM failure',
             '14' => 'SIM busy',
             '15' => 'SIM wrong',
             '16' => 'Incorrect password',
             '17' => 'SIM PIN2 required',
             '18' => 'SIM PUK2 required',
             '20' => 'Memory full',
             '21' => 'Invalid index',
             '22' => 'Not found',
             '23' => 'Memory failure',
             '24' => 'Text string too long',
             '25' => 'Invalid characters in text string',
             '26' => 'Dial string too long',
             '27' => 'Invalid characters in dial string',
             '30' => 'No network service',
             '31' => 'Network timeout',
             '32' => 'Network not allowed, emergency calls only',
             '40' => 'Network personalization PIN required',
             '41' => 'Network personalization PUK required',
             '42' => 'Network subset personalization PIN required',
             '43' => 'Network subset personalization PUK required',
             '44' => 'Service provider personalization PIN required',
             '45' => 'Service provider personalization PUK required',
             '46' => 'Corporate personalization PIN required',
             '47' => 'Corporate personalization PUK required',
             '48' => 'PH-SIM PUK required',
            '100' => 'Unknown error',
            '103' => 'Illegal MS',
            '106' => 'Illegal ME',
            '107' => 'GPRS services not allowed',
            '111' => 'PLMN not allowed',
            '112' => 'Location area not allowed',
            '113' => 'Roaming not allowed in this location area',
            '126' => 'Operation temporary not allowed',
            '132' => 'Service operation not supported',
            '133' => 'Requested service option not subscribed',
            '134' => 'Service option temporary out of order',
            '148' => 'Unspecified GPRS error',
            '149' => 'PDP authentication failure',
            '150' => 'Invalid mobile class',
            '256' => 'Operation temporarily not allowed',
            '257' => 'Call barred',
            '258' => 'Phone is busy',
            '259' => 'User abort',
            '260' => 'Invalid dial string',
            '261' => 'SS not executed',
            '262' => 'SIM Blocked',
            '263' => 'Invalid block',
            '772' => 'SIM powered down',
        }
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
DEBUG ("Start, Version $VERSION, Args: ", @all_args);
DEBUG ("Setting output to UTF-8");
binmode (STDOUT, ':utf8');

check_modemport ($modemport);

$modem_lockfile = lock_modemport  ($modemport);
if ( ! defined $modem_lockfile ) {
    print STDERR "Can't get lock file for $modemport!\n";
    print STDERR "* Wrong modem device? (use -m <dev>)?\n";
    print STDERR "* Stale lock file for $modemport in /var/lock?";
    exit $exit_error;
}

DEBUG ("Opening modem");
if ( ! open $modem_fh, '+<:raw', $modemport ) {
    print STDERR "Modem port \"$modemport\" seems in order, but cannot open it anyway:\n$!\n";
    exit $exit_error;
}

my $saved_stty_value = save_serial_opts ($modem_fh);
set_serial_opts ( $modem_fh );

DEBUG ("Initialising Expect");
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
        DEBUG ("Modem type \"$modem_model\" needs PDU format for USSD query.");
        $use_cleartext = 0;
    }
    else {
        DEBUG ("Modem type \"$modem_model\" needs cleartext for USSD query.");
        $use_cleartext = 1;
    }
}
else {
    $use_cleartext = 0;
}

if ( pin_needed() ) {
    DEBUG ("PIN needed");
    if ( ! defined $pin ) {
        print STDERR "SIM card is locked, but no PIN to unlock given.\n";
        print STDERR "Use \"-p <pin>\"!\n";
        exit $exit_nopin;
    }
    if ( enter_pin ($pin) ) {
        DEBUG ("Pin $pin accepted.");
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

DEBUG ("Shutting down");
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
    DEBUG ("END: Cleaning up");
    my $exitcode = $?;  # Save it
    if ( defined $modem_fh) {
        if ( defined $saved_stty_value ) {
            DEBUG ("END: Resetting serial interface");
            restore_serial_opts($modem_fh, $saved_stty_value);
        }
        DEBUG ("END: Closing modem interface");
        close $modem_fh;
    }
    if ( defined ($modem_lockfile) ) {
        DEBUG ("Removing lock file $modem_lockfile");
        unlock_modemport($modem_lockfile);
    }
    $? = $exitcode;
}


########################################################################
# Function: clean_exit
# Purpose:  This is the signal handler for SIGINT & SIGTERM
# Args:     $signal - Name of the caught signal
# Returns:  Nothing, just exits giving control to the END cleanup
sub clean_exit {
    my ($signal) = @_;

    if ($signal eq 'INT' ) {
        DEBUG ("INT caught, terminating");
        exit 128 + 2;
    }
    elsif ($signal eq 'TERM' ) {
        DEBUG ("TERM caught, terminating");
        exit 128 + 15; 
    }
    else {
        DEBUG ("Signal $signal caught, terminating. This should not have happened.");
        exit $exit_bug;
    }
    # NOTREACHED
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
# Function: lock_modemport
# Args:     $modem_device   - The device to set a lock file for
# Returns:  The lock file name
#           undef if no lockfilename can be worked out
sub lock_modemport {
    my ($modem_device) = @_;

    my $lock_dir        = '/var/lock';
    my ($lock_filename) = $modem_device =~ m#/([^/]*)$#;
    if ( ! defined $lock_filename || $lock_filename eq '' ) {
        print STDERR "Modem device \"$modem_device\" looks strange, can't lock it\n";
        return undef;
    }
    my $lock_file = $lock_dir . '/LCK..' . $lock_filename;
    my $lock_handle;
    if ( ! sysopen $lock_handle, $lock_file, O_CREAT|O_WRONLY|O_EXCL, 0644 ) {
        print STDERR "Can't get lockfile $lock_file - probably already in use!\n";
        return undef;
    }
    print $lock_handle "$$\n";
    close $lock_handle;
    DEBUG ("Lock $lock_file set");
    return $lock_file;
}


########################################################################
# Function: unlock_modemport
# Args:     $lock_filename   - Lockfile to delete
# Returns:  Nothing.
sub unlock_modemport {
    my ($lock_filename) = @_;

    if ( ! -f $lock_filename ) {
        DEBUG ("Lock file \"$lock_filename\" doesn't exist or is not a normal file!");
        return;
    }
    if ( ! unlink $lock_filename ) {
        DEBUG ("Can't remove lock file \"$lock_filename\": $!");
    }
}


########################################################################
# Function: save_serial_opts
# Args:     $interface   -   The file handle to remember termios values of
# Returns:  Hashref containing the termios values found
#           undef in case of errors
sub save_serial_opts {
    my ($interface) = @_;
    my $termdata;
    
    DEBUG ("Saving serial state");
    my $termios = POSIX::Termios->new();

    $termios->getattr(fileno($interface));

    $termdata->{cflag}          = $termios->getcflag();
    $termdata->{iflag}          = $termios->getiflag();
    $termdata->{lflag}          = $termios->getlflag();
    $termdata->{oflag}          = $termios->getoflag();
    $termdata->{ispeed}         = $termios->getispeed();
    $termdata->{ospeed}         = $termios->getospeed();
    $termdata->{cchars}{'INTR'} = $termios->getcc(VINTR);
    $termdata->{cchars}{'QUIT'} = $termios->getcc(VQUIT);
    $termdata->{cchars}{'ERASE'}= $termios->getcc(VERASE);
    $termdata->{cchars}{'KILL'} = $termios->getcc(VKILL);
    $termdata->{cchars}{'EOF'}  = $termios->getcc(VEOF);
    $termdata->{cchars}{'TIME'} = $termios->getcc(VTIME);
    $termdata->{cchars}{'MIN'}  = $termios->getcc(VMIN);
    $termdata->{cchars}{'START'}= $termios->getcc(VSTART);
    $termdata->{cchars}{'STOP'} = $termios->getcc(VSTOP);
    $termdata->{cchars}{'SUSP'} = $termios->getcc(VSUSP);
    $termdata->{cchars}{'EOL'}  = $termios->getcc(VEOL);

    return $termdata;
}


########################################################################
# Function: restore_serial_opts
# Args:     $interface      -   The file handle to restore termios values for
#           $termdata       -   Hashref (return value of save_serial_opts)
# Returns:  1               -   State successfully set
#           0               -   State could not be restored
sub restore_serial_opts {
    my ($interface, $termdata) = @_;
    
    DEBUG ("Restore serial state");

    my $termios = POSIX::Termios->new();

    $termios->setcflag( $termdata->{cflag} );
    $termios->setiflag( $termdata->{iflag} );
    $termios->setlflag( $termdata->{lflag} );
    $termios->setoflag( $termdata->{oflag} );
    $termios->setispeed( $termdata->{ispeed} );
    $termios->setospeed( $termdata->{ospeed} );
    $termios->setcc( VINTR, $termdata->{cchars}{'INTR'} );
    $termios->setcc( VQUIT, $termdata->{cchars}{'QUIT'} );
    $termios->setcc( VERASE,$termdata->{cchars}{'ERASE'});
    $termios->setcc( VKILL, $termdata->{cchars}{'KILL'} );
    $termios->setcc( VEOF,  $termdata->{cchars}{'EOF'}  );
    $termios->setcc( VTIME, $termdata->{cchars}{'TIME'} );
    $termios->setcc( VMIN,  $termdata->{cchars}{'MIN'}  );
    $termios->setcc( VSTART,$termdata->{cchars}{'START'});
    $termios->setcc( VSTOP, $termdata->{cchars}{'STOP'} );
    $termios->setcc( VSUSP, $termdata->{cchars}{'SUSP'} );
    $termios->setcc( VEOL,  $termdata->{cchars}{'EOL'}  );

    my $result = $termios->setattr(fileno($interface));
    if ( ! defined $result ) {
        DEBUG ("Could not restore serial state");
        return 0;
    }
    return 1;
}


########################################################################
# Function: set_serial_opts
# Args:     $interface      -   The file handle to set termios values for
# Returns:  1               -   Success
#           0               -   Failure
sub set_serial_opts {
    my ($interface) = @_;
    
    DEBUG ("Setting serial state");

    my $termios = POSIX::Termios->new();
    $termios->getattr(fileno($interface));

    $termios->setcflag( CS8 | HUPCL | CREAD | CLOCAL );
    $termios->setiflag( 0 ); # Nothing on!
    $termios->setlflag( 0 ); # Nothing on!
    $termios->setoflag( 0 );
    # $termios->setispeed( $termdata->{ispeed} ); #Autobaud
    # $termios->setospeed( $termdata->{ospeed} ); #Autobaud

    my $result = $termios->setattr(fileno($interface));
    if ( ! defined $result ) {
        DEBUG ("Could not set serial state");
        return 0;
    }
    return 1;
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

    DEBUG ("Starting modem check (AT)");
    my $result = send_command ( "AT", 'wait_for_OK' );
    if ( $result->{ok} ) {
        DEBUG ("Modem found (AT->OK)");
        return 1;
    }
    else {
        DEBUG ("No modem found, error: $result->{description}");
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
        DEBUG ("Enabling modem echo ($modem_echo_command)");
    }
    else {
        $modem_echo_command = 'ATE0';
        DEBUG ("Disabling modem echo ($modem_echo_command)");
    }

    my $result = send_command ( $modem_echo_command, 'wait_for_OK' );
    if ( $result->{ok} ) { 
        DEBUG ("$modem_echo_command successful");
        return 1;
    }   
    else {
        DEBUG ("$modem_echo_command failed, error: $result->{description}");
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

    DEBUG ("Querying modem type");
    my $result = send_command ( "AT+CGMM", 'wait_for_OK' );
    if ( $result->{ok} ) {
        DEBUG ("Modem type found: ", $result->{description} );
        return $result->{description};
    }
    else {
        DEBUG ("No modem type found: ", $result->{description});
        return undef;
    }
}


########################################################################
# Function: pin_needed
# Args:     None.
# Returns:  0   No PIN needed, SIM card is unlocked
#           1   PIN (or PUK) still needed, SIM card still locked
sub pin_needed {

    DEBUG ("Starting SIM state query (AT+CPIN?)");
    my $result = send_command ( 'AT+CPIN?', 'wait_for_OK' );
    if ( $result->{ok} ) {
        DEBUG ("Got answer for SIM state query");
        if ( $result->{match} eq 'OK') {
            if ( $result->{description} =~ m/READY/ ) {
                DEBUG ("SIM card is unlocked");
                return 0;
            }
            elsif ( $result->{description} =~ m/SIM PIN/ ) {
                DEBUG ("SIM card is locked");
                return 1;
            }
            else {
                DEBUG ("Couldn't parse SIM state query result: " . $result->{description});
                return 1;
            }
        }
        else {
            DEBUG ("SIM card locked - failed query? -> " . $result->{match} );
            return 1;
        }
    }
    else {
        DEBUG (" SIM state query failed, error: " . $result->{description} );
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

    DEBUG ("Unlocking SIM using PIN $pin");
    my $result = send_command ( "AT+CPIN=$pin", 'wait_for_OK' );
    if ( $result->{ok} ) {
        DEBUG ("SIM card unlocked: ", $result->{match} );
        return 1;
    }
    else {
        DEBUG ("SIM card still locked, error: ", $result->{description});
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

    DEBUG ("Waiting for net registration, max $max_tries tries");
    while ($num_tries <= $max_tries) {
        DEBUG ("Try: $num_tries");
        my $result = send_command ( 'AT+CREG?', 'wait_for_OK' );
        if ( $result->{ok} ) {
            DEBUG ('Net registration query result received, parsing');
            my ($n, $stat) = $result->{description} =~ m/\+CREG:\s+(\d),(\d)/i;
            if ( ! defined $n || ! defined $stat) {
                $last_state_message = 'Cannot parse +CREG answer: ' . $result->{description}; 
                DEBUG ( $last_state_message );
                return ( 0, $last_state_message );
            }
            if ( $stat == 0 ) {
                $last_state_message = 'Not registered, MT not searching a new operator to register to';
                DEBUG ( $last_state_message );
                return ( 0, $last_state_message );
            }
            elsif ( $stat == 1 ) {
                $last_state_message = 'Registered, home network';
                DEBUG ( $last_state_message );
                if ( $num_tries != 1 ) {
                    DEBUG ( 'Sleeping one more time for settling in');
                    sleep $wait_time_between_net_checks;
                }
                return ( 1, $last_state_message );
            }
            elsif ( $stat == 2 ) {
                $last_state_message = 'Not registered, currently searching new operator to register to';
                DEBUG ( $last_state_message );
            }
            elsif ( $stat == 3) {
                $last_state_message = 'Registration denied'; 
                DEBUG ( $last_state_message );
                return ( 0, $last_state_message );
            }
            elsif ( $stat == 4) {
                $last_state_message = 'Registration state unknown';
                DEBUG ( $last_state_message );
            }
            elsif ( $stat == 5 ) {
                $last_state_message = 'Registered, roaming';
                DEBUG ( $last_state_message );
                if ( $num_tries != 1 ) {
                    DEBUG ( 'Sleeping one more time for settling in');
                    sleep $wait_time_between_net_checks;
                }
                return ( 1, $last_state_message );
            }
            else {
                $last_state_message = "Cannot understand net reg state code $stat";
                DEBUG ( $last_state_message );
            }
        }
        else {
            $last_state_message = 'Querying net registration failed, error: ' . $result->{description}; 
            DEBUG ( $last_state_message );
            return ( 0, $last_state_message );
        }
        DEBUG ("Sleeping for $wait_time_between_net_checks seconds");
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

    DEBUG ("Starting USSD query \"$query\"");

    my $result = send_command (
        ussd_query_cmd($query, $use_cleartext),
        'wait_for_cmd_answer',
    );

    if ( $result->{ok} ) {
        DEBUG ("USSD query successful, answer received");
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
            DEBUG ("Can't parse CUSD message: \"", $result->{description}, "\"");
            return {
                ok  => $fail,
                msg =>  "Can't understand modem answer: \""
                        . $result->{description} . "\"",
            };
        }
        elsif ( $response_type == 0 ) {
            DEBUG ("USSD response type: No further action required (0)");
        }
        elsif ( $response_type == 1 ) {
            DEBUG ("USSD response type: Further action required (1)");
            print STDERR "USSD session open, to cancel use \"gsm-ussd -c\".\n";
        }
        elsif ( $response_type == 2 ) {
            my $msg = "USSD response type: USSD terminated by network (2)";
            DEBUG ($msg);
        }
        elsif ( $response_type == 3 ) {
            my $msg = ("USSD response type: Other local client has responded (3)");
            DEBUG ($msg);
            return { ok => $fail, msg => $msg };
        }
        elsif ( $response_type == 4 ) {
            my $msg = ("USSD response type: Operation not supported (4)");
            DEBUG ($msg);
            return { ok => $fail, msg => $msg };
        }
        elsif ( $response_type == 5 ) {
            my $msg = "USSD response type: Network timeout (5)";
            DEBUG ($msg);
            return { ok => $fail, msg => $msg };
        }
        else {
            my $msg = "CUSD message has unknown response type \"$response_type\"";
            DEBUG ($msg);
            return { ok => $fail, msg => $msg };
        }
        # Only reached if USSD response type is 0 or 1
        return { ok => $success, msg => interpret_ussd_data ($response, $encoding) };
    }
    else {
        DEBUG ("USSD query failed, error: " . $result->{description});
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

    DEBUG ('Trying to cancel USSD session');
    my $result = send_command ( "AT+CUSD=2\r", 'wait_for_OK' );
    if ( $result->{ok} ) {
        my $msg = 'USSD cancel request successful';
        DEBUG ($msg);
        return { ok => $success, msg => $msg };
    }
    else {
        my $msg = 'No USSD session to cancel.';
        DEBUG ($msg);
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
        DEBUG ("CUSD message has no encoding, interpreting as cleartext");
        return $response;
    }

    if ( dcs_is_default_alphabet ( $encoding ) ) {
        DEBUG ("Encoding \"$encoding\" says response is in default alphabet");
        if ( $use_cleartext ) {
            DEBUG ("Modem uses cleartext, interpreting message as cleartext");
            return $response;
        }
        elsif ( $encoding == 0 ) {
            return hex_to_string( $response );
        }
        elsif ( $encoding == 15 ) {
            return decode ('gsm0338', gsm_unpack( hex_to_string( $response )));
        }
        else {
            DEBUG ("CUSD message has unknown encoding \"$encoding\", using 0");
            return hex_to_string( $response );
        }
        # NOTREACHED
    }
    elsif ( dcs_is_ucs2 ( $encoding ) ) {
        DEBUG ("Encoding \"$encoding\" says response is in UCS2-BE");
        return decode ('UCS-2BE', hex_to_string ($response));
    }
    elsif ( dcs_is_8bit ( $encoding ) ) {
        DEBUG ("Encoding \"$encoding\" says response is in 8bit");
        return hex_to_string ($response); # Should this be cleartext?
    }
    else {
        DEBUG ("CUSD message has unknown encoding \"$encoding\", using 0");
        return hex_to_string( $response );
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

    DEBUG ("Sending command: $cmd");
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
            my $errormessage = translate_gms_error($first_word,$args);
            return {
                ok          => $fail,
                match       => $match_string,
                description => "GSM network error: $errormessage ($args)",
            };
        }
        elsif ( $first_word eq '+CME ERROR' ) {
            # After this error there will be no OK/ERROR anymore
            my $errormessage = translate_gsm_error($first_word,$args);
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

    DEBUG("$state_name: $result, ignored");
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

    DEBUG ("Network error $error_msg_type with data \"$error_msg_value\" detected.");
}


########################################################################
# Function: ussd_query_cmd
# Args:     The USSD-Query to send 
# Returns:  An AT+CUSD command with properly encoded args
sub ussd_query_cmd {
	my ($ussd_cmd)                  = @_;
	my $result_code_presentation    = '1';      # Enable result code presentation
	my $encoding                    = '15';     # No clue what this value means
	my $ussd_string;

    if ( $use_cleartext ) {
        $ussd_string = $ussd_cmd;
    }
    else {
        $ussd_string = string_to_hex (gsm_pack (encode('gsm0338', $ussd_cmd)));
    }
	return sprintf 'AT+CUSD=%s,"%s",%s', $result_code_presentation, $ussd_string, $encoding;
}


########################################################################
# Function: translate_gsm_error
# Args:     $error_type -  "CMS ERROR" or "CME ERROR"
#           CME ERRORs are equipment related errors (missing SIM etc.)
#           CMS ERRORs are network related errors
#           $error_number - the error number to translate
#           If the error number ist found not be a unsigned integer,
#           it it returned as is - we were probably given a clear
#           text error message
# Returns:  The error message corresponding to the error number
#           GSM error codes found at 
#           http://www.activexperts.com/xmstoolkit/sms/gsmerrorcodes/
sub translate_gsm_error {
    my ($error_type, $error_number) = @_;
    
    if ( $error_number !~ /^\d+$/ ) {
        # We have probably been given an already readable error message.
        # The E160 is strange: Some error messages are english, some
        # are plain numbers!
        return $error_number;
    }
    elsif ( exists $gsm_error{$error_type}{$error_number} ) {
        # Translate the number into message
        return $gsm_error{$error_type}{$error_number} ;
    }
    # Number not found
    return 'No error description available';
}


#######################################################################r
# Function: hex_to_string
# Args:     String consisting of hex values
# Returns:  String containing the given values
sub hex_to_string {
	return pack ("H*", $_[0]);
}


########################################################################
# Function: string_to_hex
# Args:     String 
# Returns:  Hexstring
sub string_to_hex {
	return uc( unpack( "H*", $_[0] ) );
}


########################################################################
# Function: repack_bits
# Args:     $count_bits_in  Number of bits per arg list element
#           $count_bits_out Number of bits per result list element
#           $bit_values_in  String containing $count_bits_in bits per
#                           char
# Returns:  String containing $count_bits_out bits per char. From a "bit
#           stream" point of view, nothing is changed,
#           only the number of bits per char in arg and result string
#           differ!
#
# This function is really only tested packing/unpacking 7 bit values to
# 8 bit values and vice versa. As this function uses bit operators,
# it'll probably work up to a maximum element size of 16 bits (both in
# and out). If you're running on an 64 bit platform, it might even work
# with elements up to 32 bits length. *Those are guesses, as I didn't
# test this!*
sub repack_bits {
    my ($count_bits_in, $count_bits_out, $bit_values_in) = @_;

    my $bit_values_out	= '';
    my $bits_in_buffer	= 0;
    my $bitbuffer		= 0;
    my $bit_mask_out    = 2**$count_bits_out - 1;

    for (my $pos = 0; $pos < length ($bit_values_in); ++$pos) {
        my $in_bits = ord (substr($bit_values_in, $pos, 1));
		# Die neuen Bits soweit linksshiften, wie noch Bits
		# im Buffer sind und mit dem Buffer ORen.
		# Die vorhandenen Bits um x Bits linksshiften
		$bitbuffer = $bitbuffer | ( $in_bits << $bits_in_buffer);
		$bits_in_buffer += $count_bits_in;

		while ( $bits_in_buffer >= $count_bits_out ) {
			# Die letzten y Bits ausspucken
			$bit_values_out .= chr ( $bitbuffer & $bit_mask_out ) ;
			$bitbuffer = $bitbuffer >> $count_bits_out;
			$bits_in_buffer -= $count_bits_out;
		}	
	}
	# Rest im Buffer inkl. Null-Fuellbits ausgeben
	if ($count_bits_in < $count_bits_out && $bits_in_buffer > 0) {
        $bit_values_out .= chr ( $bitbuffer & $bit_mask_out ) ;
	}

	return $bit_values_out;
}


########################################################################
# Function: gsm_unpack
# Args:     String to unpack 7 bit values from
# Returns:  String containing 7 bit values of the arg per character
sub gsm_unpack {
	return repack_bits (8,7, $_[0]);
}


########################################################################
# Function: gsm_pack
# Args:     String of 7 bit values to pack (8 7 bit values into 7 eight
#           bit values)
# Returns:  String containing 7 bit values of the arg per character
sub gsm_pack {
	return repack_bits(7, 8, $_[0]);
}


#######################################################################
# Function: dcs_is_default_alphabet
# Args:     $enc    - the USSD dcs
# Returns:  1   - dcs indicates default alpabet
#           0   - dcs does not indicate default alphabet
sub dcs_is_default_alphabet {
    my ($enc) = @_;

    if ( ! bit_is_set (6, $enc) && ! bit_is_set (7, $enc) ) {
        return 1;
    }
    if (     bit_is_set(6, $enc)
        && ! bit_is_set (7, $enc)
        && ! bit_is_set (2, $enc)
        && ! bit_is_set (3, $enc)
    ) {
        return 1;
    }
    return 0;
}


#######################################################################
# Function: dcs_is_ucs2
# Args:     $enc    - the USSD dcs
# Returns:  1   - dcs indicates UCS2-BE
#           0   - dcs does not indicate UCS2-BE
sub dcs_is_ucs2 {
    my ($enc) = @_;

    if (     bit_is_set (6, $enc)
        && ! bit_is_set (7, $enc)
        && ! bit_is_set (2, $enc)
        &&   bit_is_set (3, $enc)
    ) {
        return 1;
    }
    return 0;
}


#######################################################################
# Function: dcs_is_8bit
# Args:     $enc    - the USSD dcs
# Returns:  1   - dcs indicates 8bit
#           0   - dcs does not indicate 8bit
sub dcs_is_8bit {
    my ($enc) = @_;

    if (     bit_is_set (6, $enc)
        && ! bit_is_set (7, $enc)
        &&   bit_is_set (2, $enc)
        && ! bit_is_set (3, $enc)
    ) {
        return 1;
    }
    return 0;
}


########################################################################
# Function: bit_is_set
# Args:     $bit - Number of the bit to test
#           $val - Value to test bit $bit against
# Returns:  1   - Bit is set to 1
#           0   - Bit is set to 0
sub bit_is_set {
    my ($bit, $val) = @_;
    return $val & ( 2 ** $bit );
}


########################################################################
# Function: DEBUG
# Args:     Strings to print with a [DEBUG] prefix
# Returns:  Void
sub DEBUG {
    if ($debug) {
        print STDERR '[DEBUG] ' . join(' ',@_) . $/ ;
    }
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
