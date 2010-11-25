#!/usr/bin/perl
########################################################################
# vim: set expandtab sw=4 ts=4 ai nu: 
########################################################################

package GSMUSSD::Modem;

use strict;
use warnings;
# use 5.008;                  # Encode::GSM0338 only vailable since 5.8

use Carp;

use GSMUSSD::Loggit;
use GSMUSSD::Stty;
use GSMUSSD::Lockfile;
use GSMUSSD::NetworkErrors;

use Expect;     # External dependency


########################################################################
# Class variables
########################################################################

my $wait_time_between_net_checks    = 3;
my $fail    = 0;
my $success = 1;

# Possible modem answers
my %modem_answer = (
        # Fail states of the network
        cms_error  =>  [
            qr/\r\n\+(CMS ERROR):[ ]*([^\r\n]*)\r\n/i
                => \&_network_error
        ],
        # Fail states of the modem equipment
        cme_error  =>  [
            qr/\r\n\+(CME ERROR):[ ]*([^\r\n]*)\r\n/i
                => \&_network_error
        ],
        # AT command (TTY echo of input)
        at          =>  [
            qr/^AT([^\r\n]*)\r/i
                => \&_at_found
        ],
        ok          =>  [
            qr/\r\nOK\r\n/i
                =>  \&_ok
        ],
        # Command failed, probably not correct syntax
        error       =>  [
            qr/\r\nERROR\r\n/i
                =>  \&_error
        ],
);


########################################################################
# Method:   new
# Type:     Constructor
# Args:     
sub new {
	my ($class, $device,$modem_timeout, $modem_chatlog) = @_;
	
    carp "No device for modem given" 
        if not defined $device;
    $modem_timeout = 20
        if not defined $modem_timeout;

	my $self = {
        device                  =>  $device,
        device_handle           =>  undef,
        modem_timeout           =>  $modem_timeout,
        expect                  =>  undef,
        modem_chatlog           =>  $modem_chatlog,
        registration_retries    =>  10,
        log                     =>  GSMUSSD::Loggit->new(),
        lock                    =>  GSMUSSD::Lockfile->new($device),
        stty                    =>  undef,
        error                   =>  undef,
        model                   =>  undef,
        # manufacturer            =>  undef,
        match                   =>  '',
        description             =>  '',
    };
	bless $self, $class;
    

	return $self;
}


########################################################################
# Getter
sub error {
    my ($self) = @_;
    
    return $self->{error};
}


########################################################################
# Getter
sub match {
    my ($self) = @_;
    
    return $self->{match};
}


########################################################################
# Getter
sub description {
    my ($self) = @_;
    
    return $self->{description};
}


########################################################################
sub open {
    my ($self) = @_;

    $self->{log}->DEBUG ('Locking device');
    if ( ! $self->{lock}->lock() ) {
        $self->{error} = "Can't lock $self->{device}";
        return 0;
    }

    $self->{log}->DEBUG ('Opening device');
    if ( ! open $self->{device_handle}, '+<:raw', $self->{device} ) {
        $self->{error} = "Modem port \"$self->{device}\" seems in order, but cannot open it anyway:\n$!\n";
        return 0;
    }

    $self->{log}->DEBUG ('Set stty settings for device');
    $self->{stty} = GSMUSSD::Stty->new($self->{device_handle});
    $self->{stty}->save();  # Errors?
    $self->{stty}->set_raw_noecho();

    $self->{log}->DEBUG ('Initialising Expect');
    $self->{expect}	= Expect->exp_init($self->{device_handle});
    if ( defined $self->{modem_chatlog} ) {
        $self->{expect}->log_file($self->{modem_chatlog}, 'w');
    }
    return 1;
}


########################################################################
# Method:   close
# Args:     None.
# Returns:  None.
sub close {
    my ($self) = @_;

    if ( defined $self->{stty} ) {
        $self->{stty}->restore();
        $self->{stty} = undef;
    }
    if ( defined $self->{expect} ) {
        $self->{expect}->hard_close();
        $self->{expect} = undef;
    }
    if ( defined $self->{device_handle} ) {
        close $self->{device_handle};
        $self->{device_handle} = undef;
    }
    if ( defined $self->{lock} ) {
        $self->{lock} = undef;
    }
}


########################################################################
# Method:   send_command
# Args:     $cmd        String holding the command to send (usually 
#                       something like "AT...")
# Returns:  $fail       Response was ERROR or CM[SE] ERROR
#           $success    Response was OK
sub send_command {
    my ($self, $cmd)	= @_;

    $self->{log}->DEBUG ("Sending command: $cmd");
    $self->{expect}->send("$cmd\015");

    my (
        $matched_pattern_pos,
        $error,
        $match_string,
        $before_match,
        $after_match
    ) =
    $self->{expect}->expect (
            $self->{modem_timeout},
            $modem_answer{at},  # Will not be reported due to exp_continue
            $modem_answer{ok},
            $modem_answer{error},
            $modem_answer{cms_error},
            $modem_answer{cme_error},
    );

    if ( ! defined $error ) {
        if ( $matched_pattern_pos == 1 ) {
            # Can't happen, AT exp_continues!
        }
        elsif ( $matched_pattern_pos == 2 ) {
            # OK
            # $before_match contains data between AT and OK
            $before_match =~ s/(?:^\s+|\s+$)//g;    # crop whitespace
            $match_string =~ s/(?:^\s+|\s+$)//g;    # crop whitespace
            $self->{match}          = $match_string;
            $self->{description}    = $before_match;
            return $success;
        }
        elsif ( $matched_pattern_pos == 3 ) {
            # ERROR 
            $self->{match}          = $match_string;
            $self->{description}    = 'Broken modem command';
            return $fail;
        }
        elsif ( $matched_pattern_pos == 4 ) {
            # After this error there will be no OK/ERROR anymore
            my $cms_value       = ($self->{expect}->matchlist())[1];
            my $errormessage    = GSMUSSD::NetworkErrors->new()->get_cms_error($cms_value);
            $self->{match}          = $match_string;
            $self->{description}    = "GSM network error: $errormessage ($cms_value)";
            return $fail;
        }
        elsif ( $matched_pattern_pos == 5 ) {
            # After this error there will be no OK/ERROR anymore
            my $cme_value       = ($self->{expect}->matchlist())[1];
            my $errormessage    = GSMUSSD::NetworkErrors->new()->get_cme_error($cme_value);
            $self->{match}          = $match_string;
            $self->{description}    = "GSM equipment error: $errormessage ($cme_value)";
            return $fail;
        }
        # elsif ( $first_word =~ /^[\^\+]/ ) {
        #    $self->{match}       = $match_string;
        #    $self->{description} = $match_string;
        #    return $success;
        #}
        else {
            $self->{match}       = $match_string;
            $self->{description} = "PANIC! Unexpected matched pattern!";
            return $fail;
        }
    }
    else {
        # Report Expect error and bail
        if ($error =~ /^1:/) {
            # Timeout
            $self->{match}       = $error;
            $self->{description} = "No answer for $self->{modem_timeout} seconds!";
            return $fail;
        }
        elsif ($error =~ /^2:/) {
            # EOF
            $self->{match}       = $error;
            $self->{description} = "EOF from modem received - modem unplugged?";
            return $fail;
        }
        elsif ($error =~ /^3:/) {
            # Spawn id died
            $self->{match}       = $error;
            $self->{description} = "PANIC! Can't happen - spawn ID died!";
            return $fail;
        }
        elsif ($error =~ /^4:/) {
            # Read error
            $self->{match}       = $error;
            $self->{description} = "Read error accessing modem: $!";
            return $fail;
        }
        else {
            $self->{match}       = $error;
            $self->{description} = "PANIC! Can't happen - unknown Expect error \"$error\"";
            return $fail;
        }
    }
    $self->{match}       = '';
    $self->{description} = "PANIC! Can't happen - left send_command() unexpectedly!";
    return $fail;
}


########################################################################
# Method:   wait_for
# Args:     $pattern    Pattern to match in modem output
# Returns:  $success if pattern matched
#           $fail if timed out
sub wait_for {
    my ($self, $pattern)	= @_;

    $self->{log}->DEBUG ("Waiting for pattern: $pattern");

    my (
        $matched_pattern_pos,
        $error,
        $match_string,
        $before_match,
        $after_match
    ) =
    $self->{expect}->expect (
            $self->{modem_timeout},
            '-re', qr/$pattern/,
            $modem_answer{error},       # Needed?
            $modem_answer{cms_error},
            $modem_answer{cme_error},
    );

    if ( ! defined $error ) {
        if ( $matched_pattern_pos == 1 ) {
            $self->{log}->DEBUG ("Given pattern found");
            $before_match =~ s/(?:^\s+|\s+$)//g;    # crop whitespace
            $self->{match}          = $match_string;
            $self->{description}    = $before_match;
            return $success;
        }
        elsif ( $matched_pattern_pos == 2 ) {
            $self->{match}       = $match_string;
            $self->{description} = 'Broken modem command';
            return $fail;
        }
        elsif ( $matched_pattern_pos == 3 ) {
            my $cms_value       = ($self->{expect}->matchlist())[1];
            my $errormessage    = GSMUSSD::NetworkErrors->new()->get_cms_error($cms_value);
            $self->{match}      = $match_string;
            $self->{description} = "GSM network error: $errormessage ($cms_value)";
            return $fail;
        }
        elsif ( $matched_pattern_pos == 4 ) {
            my $cme_value       = ($self->{expect}->matchlist())[1];
            my $errormessage    = GSMUSSD::NetworkErrors->new()->get_cme_error($cme_value);
            $self->{match}      = $match_string;
            $self->{description} = "GSM equipment error: $errormessage ($cme_value)";
            return $fail;
        }
        else {
            $self->{match}       = $match_string;
            $self->{description} = "PANIC! Can't parse Expect result: \"$match_string\"";
            return $fail;
        }
    }
    else {
        # Report Expect error and bail
        if ($error =~ /^1:/) {
            # Timeout
            $self->{match}       = $error;
            $self->{description} = "No answer for $self->{modem_timeout} seconds!";
            return $fail;
        }
        elsif ($error =~ /^2:/) {
            # EOF
            $self->{match}       = $error;
            $self->{description} = "EOF from modem received - modem unplugged?";
            return $fail;
        }
        elsif ($error =~ /^3:/) {
            # Spawn id died
            $self->{match}       = $error;
            $self->{description} = "PANIC! Can't happen - spawn ID died!";
            return $fail;
        }
        elsif ($error =~ /^4:/) {
            # Read error
            $self->{match}       = $error;
            $self->{description} = "Read error accessing modem: $!";
            return $fail;
        }
        else {
            $self->{match}       = $error;
            $self->{description} = "PANIC! Can't happen - unknown Expect error \"$error\"";
            return $fail;
        }
    }
    $self->{match}       = '';
    $self->{description} = "PANIC! Can't happen - left send_command() unexpectedly!";
    return $fail;
}


########################################################################
# Method:   probe
# Args:     None
# Returns:  0   No modem found 
#           1   Modem found
#
# "Finding a modem" is hereby defined as getting a reaction of "OK"
# to writing "AT" into the file handle in question.
sub probe {
    my ($self) = @_;

    $self->{log}->DEBUG ("Probing modem (AT)");
    my $probe_ok = $self->send_command ( "AT" );
    if ( $probe_ok ) {
        $self->{log}->DEBUG ("Modem found (AT->OK)");
        return 1;
    }
    else {
        $self->{log}->DEBUG ("No modem found, error: $self->{description}");
        $self->{error} = $self->{description};
        return 0;
    }
}


########################################################################
# Method:   echo
# Args:     true    -   Echo on
#           false   -   Echo off
# Returns:  0   -   Success
#           1   -   Fail 
sub echo {
    my ($self, $echo_on) = @_;
    my $modem_echo_command = '';

    if (defined $echo_on && $echo_on != 0) {
        $modem_echo_command = 'ATE1';
        $self->{log}->DEBUG ("Enabling modem echo ($modem_echo_command)");
    }
    else {
        $modem_echo_command = 'ATE0';
        $self->{log}->DEBUG ("Disabling modem echo ($modem_echo_command)");
    }

    my $echo_ok = $self->send_command ( $modem_echo_command );
    if ( $echo_ok ) { 
        $self->{log}->DEBUG ("$modem_echo_command successful");
        return 1;
    }   
    else {
        $self->{log}->DEBUG ("$modem_echo_command failed, error: $self->{description}");
        $self->{error} = $self->{description};
        return 0;
    }   
}


########################################################################
# Method:   pin_needed
# Args:     None.
# Returns:  0   No PIN needed, SIM card is unlocked
#           1   PIN (or PUK) needed, SIM card locked
sub pin_needed {
    my ($self) = @_;

    $self->{log}->DEBUG ("Starting SIM state query (AT+CPIN?)");

    my $pin_ok = $self->send_command( 'AT+CPIN?' );
    if ( $pin_ok ) {
        $self->{log}->DEBUG ("Got answer for SIM state query");

        if ( $self->{match} eq 'OK') {
            if ( $self->{description} =~ m/READY/ ) {
                $self->{log}->DEBUG ("SIM card is unlocked");
                return 0;
            }
            elsif ( $self->{description} =~ m/SIM PIN/ ) {
                $self->{log}->DEBUG ("SIM card is locked");
                return 1;
            }
            else {
                $self->{log}->DEBUG ("Couldn't parse SIM state query result: $self->{description}");
                return 1;
            }
        }
        else {
            $self->{log}->DEBUG ("SIM card locked - failed query? -> $self->{match}" );
            return 1;
        }
    }
    else {
        $self->{log}->DEBUG ("SIM state query failed, error: $self->{description}" );
        return 1;
    }
}


########################################################################
# Method:   model
# Args:     None
# Returns:  String  Name of the modem model
#           undef   No name found
#
# Different modems report *very* different things here, but it's enough
# to see if it's a E160-type modem.
sub model {
    my ($self) = @_;

    if ( defined $self->{model} ) {
        $self->{log}->DEBUG ("Modem model $self->{model} cached");
        return $self->{model};
    }

    $self->{log}->DEBUG ("Querying modem type");
    my $model_ok = $self->send_command ( "AT+CGMM" );
    if ( $model_ok ) {
        $self->{log}->DEBUG ("Modem type found: ", $self->{description} );
        $self->{model} = $self->{description};
        return $self->{model};
    }
    else {
        $self->{log}->DEBUG ("No modem type found: ", $self->{description});
        return '';
    }
}


########################################################################
# Method:   enter_pin
# Args:     The PIN to unlock the SIM card
# Returns:  0   Unlocking the SIM card failed
#           1   SIM is now unlocked
sub enter_pin {
    my ($self, $pin) = @_;

    $self->{log}->DEBUG ("Unlocking SIM using PIN $pin");
    my $pin_ok = $self->send_command ( "AT+CPIN=\"$pin\"" );
    if ( $pin_ok ) {
        $self->{log}->DEBUG ("SIM card unlocked: ", $self->{match} );
        return 1;
    }
    else {
        $self->{log}->DEBUG ("SIM card still locked, error: ", $self->{description});
        $self->{error} = $self->{description};
        return 0;
    }
}


########################################################################
# Method:   get_net_registration_state
# Args:     None
# Returns:  0 - No net available
#           1 - Modem is registered in a net
sub get_net_registration_state {
    my ($self)              = @_;

    my $num_tries           = 1;
    my $last_state_message  = '';

    $self->{log}->DEBUG ("Waiting for net registration, max $self->{registration_retries} tries");
    while ( $num_tries <= $self->{registration_retries} ) {
        $self->{log}->DEBUG ("Try: $num_tries");
        my $reg_ok = $self->send_command ( 'AT+CREG?' );
        if ( $reg_ok ) {
            $self->{log}->DEBUG ('Net registration query result received, parsing');
            my ($n, $stat) = $self->{description} =~ m/\+CREG:\s+(\d),(\d)/i;
            if ( ! defined $n || ! defined $stat) {
                $last_state_message = 'Cannot parse +CREG answer: ' . $self->{description}; 
                $self->{log}->DEBUG ( $last_state_message );
                return ( 0, $last_state_message );
            }
            if ( $stat == 0 ) {
                $last_state_message = 'Not registered, MT not searching a new operator to register to';
                $self->{log}->DEBUG ( $last_state_message );
                return ( 0, $last_state_message );
            }
            elsif ( $stat == 1 ) {
                $last_state_message = 'Registered, home network';
                $self->{log}->DEBUG ( $last_state_message );
                if ( $num_tries != 1 ) {
                    $self->{log}->DEBUG ( 'Sleeping one more time for settling in');
                    sleep $wait_time_between_net_checks;
                }
                return ( 1, $last_state_message );
            }
            elsif ( $stat == 2 ) {
                $last_state_message = 'Not registered, currently searching new operator to register to';
                $self->{log}->DEBUG ( $last_state_message );
            }
            elsif ( $stat == 3) {
                $last_state_message = 'Registration denied'; 
                $self->{log}->DEBUG ( $last_state_message );
                return ( 0, $last_state_message );
            }
            elsif ( $stat == 4) {
                $last_state_message = 'Registration state unknown';
                $self->{log}->DEBUG ( $last_state_message );
            }
            elsif ( $stat == 5 ) {
                $last_state_message = 'Registered, roaming';
                $self->{log}->DEBUG ( $last_state_message );
                if ( $num_tries != 1 ) {
                    $self->{log}->DEBUG ( 'Sleeping one more time for settling in');
                    sleep $wait_time_between_net_checks;
                }
                return ( 1, $last_state_message );
            }
            else {
                $last_state_message = "Cannot understand net reg state code $stat";
                $self->{log}->DEBUG ( $last_state_message );
            }
        }
        else {
            $last_state_message = 'Querying net registration failed, error: ' . $self->{description}; 
            $self->{log}->DEBUG ( $last_state_message );
            return ( 0, $last_state_message );
        }
        $self->{log}->DEBUG ("Sleeping for $wait_time_between_net_checks seconds");
        sleep $wait_time_between_net_checks;
        ++ $num_tries;
    }
    return ( 0, "No net registration in $self->{registration_retries} tries found, last result:\n$last_state_message" );
}

########################################################################
########################################################################
########################################################################

########################################################################
# Method:   device_accessible
# Args:     None
# Returns:  
sub device_accessible {
    my ($self) = @_;

    my $dev = $self->{device};
    if ( -e $dev && -c $dev && -r $dev && -w $dev ) {
        return 1;
    }
    return 0;
}


########################################################################
# Function: _network_error
# Args:     $exp        The Expect object in use
#           $state_msg_result  Value of state message
# Returns:  Nothing, will end the expect() call
sub _network_error {
    my $exp = shift;
    my ($error_msg_type,$error_msg_value) = $exp->matchlist();

    GSMUSSD::Loggit->new()->DEBUG ("Network error $error_msg_type with data \"$error_msg_value\" detected.");
}


sub _at_found {
    my $exp = shift;

    GSMUSSD::Loggit->new()->DEBUG( 'AT found, -> ', $exp->match() );
    exp_continue_timeout;
}


sub _ok {
    my $exp = shift;

    GSMUSSD::Loggit->new()->DEBUG( 'OK found.' );
}


sub _error {
    my $exp = shift;

    GSMUSSD::Loggit->new()->DEBUG( 'ERROR found.' );
}


########################################################################
__END__

=head1 NAME

GSMUSSD::DCS

=head1 SYNOPSYS

 use GSMUSSD::DCS;

 my $dcs = GSMUSSD::DCS->new( $dcs_from_ussd_answer );
 if ( $dcs->is_8bit() ) {
    print "Simple hexstring to value conversion suffices!\n");
 }

=head1 DESCRIPTION

=head1 AUTHOR

Jochen Gruse, L<mailto:jochen@zum-quadrat.de>

