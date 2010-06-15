#!/usr/bin/perl
########################################################################
# vim: set expandtab sw=4 ts=4 ai nu: 
########################################################################
# Module:           GSMUSSD::UssdQuery
# Documentation:    POD at __END__
########################################################################

package GSMUSSD::UssdQuery;

use strict;
use warnings;

use Encode qw(encode decode);
use Carp;
use Scalar::Util    qw/blessed/;

use GSMUSSD::Loggit;
use GSMUSSD::DCS;
use GSMUSSD::Code;
use GSMUSSD::Modem;

########################################################################
# Class variables
########################################################################

# This is a list of modems that need the PDU format for query
# As of now, these are all Huaweis...
my %pdu_modem = (
    ''          => 0,   # In case modem type can not be found
    'default'   => 0,   # Fallback if modem type not in list
    'E160'      => 1,
    'E160X'     => 1,
    'E165G'     => 1,
    'E1550'     => 1,
);

my $fail    = 0;
my $success = 1;

########################################################################
# Method:   new
# Type:     Constructor
# Args:     None
sub new {
    my ($class, $modem, $use_cleartext) = @_;

    if ( ! defined blessed ($modem)  ) {
        croak "Give me a modem";
    }
    if ( ! $modem->isa('GSMUSSD::Modem' )  ) {
        croak "Give me a real modem";
    }

    my $self = {
        log                     => GSMUSSD::Loggit->new(),
        modem                   => $modem,
        modem_uses_cleartext    => 0,
        session                 => 0,
    };
    bless $self, $class;

    if ( ! defined $use_cleartext ) {
        if ( $self->modem_needs_pdu_format() ) {
            $self->{log}->DEBUG ('Modem type needs PDU format for USSD query:', $self->{modem}->model() );
            $self->{modem_uses_cleartext} = 0;
        }
        else {
            $self->{log}->DEBUG ('Modem type needs cleartext for USSD query:', $self->{modem}->model() );
            $self->{modem_uses_cleartext} = 1;
        }
    }
    else {
        $self->{log}->DEBUG( 'Will use cleartext as given: ', $use_cleartext );
        $self->{modem_uses_cleartext} = $use_cleartext;
    }

    return $self;
}

sub is_in_session {
    my ($self) = @_;

    return $self->{session};
}


########################################################################
# Method:   modem_needs_pdu_format
# Args:     $model - The model type reported by the modem
# Returns:  0   -   Modem type needs cleartext USSD query
#           1   -   Modem type needs PDU format
sub modem_needs_pdu_format {
    my ($self) = @_;

    my $model = $self->{modem}->model();
    if ( ! exists $pdu_modem{$model} ) {
        $model = 'default';
    }
    return $pdu_modem{$model};
}


########################################################################
# Method:   is_valid_ussd_query
# Args:     $query - The USSD query to check
# Returns:  0   -   Query contains illegal characters
#           1   -   Query is legal
sub is_valid_ussd_query {
    my ( $self, $query ) = @_;

    # The first RA checks for a "standard" USSD
    # The second allows simple numbers as used by USSD sessions
    if ( $query =~ m/^\*[0-9*]+#$/ || $query =~ m/^\d+$/) {
        return 1;
    }
    return 0;
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
    my ( $self, $query ) = @_;

    $self->{log}->DEBUG ('Starting USSD query', $query);

    my $result = $self->{modem}->send_command (
        $self->ussd_query_cmd($query),
        'wait_for_cmd_answer',
    );

    if ( $result->{ok} ) {
        $self->{log}->DEBUG ("USSD query successful, answer received");
        my ($response_type,$response,$dcs)
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
            $self->{log}->DEBUG ("Can't parse CUSD message: \"", $result->{description}, "\"");
            return {
                ok  => $fail,
                msg =>  "Can't understand modem answer: \""
                        . $result->{description} . "\"",
            };
        }
        elsif ( $response_type == 0 ) {
            $self->{log}->DEBUG ("USSD response type: No further action required (0)");
            $self->{session} = 0;
        }
        elsif ( $response_type == 1 ) {
            $self->{log}->DEBUG ("USSD response type: Further action required (1)");
            $self->{session} = 1; # print STDERR "USSD session open, to cancel use \"gsm-ussd -c\".\n";
        }
        elsif ( $response_type == 2 ) {
            my $msg = "USSD response type: USSD terminated by network (2)";
            $self->{log}->DEBUG ($msg);
            $self->{session} = 0;
            return { ok => $fail, msg => $msg };
        }
        elsif ( $response_type == 3 ) {
            my $msg = ("USSD response type: Other local client has responded (3)");
            $self->{log}->DEBUG ($msg);
            $self->{session} = 0;
            return { ok => $fail, msg => $msg };
        }
        elsif ( $response_type == 4 ) {
            my $msg = ("USSD response type: Operation not supported (4)");
            $self->{log}->DEBUG ($msg);
            $self->{session} = 0;
            return { ok => $fail, msg => $msg };
        }
        elsif ( $response_type == 5 ) {
            my $msg = "USSD response type: Network timeout (5)";
            $self->{log}->DEBUG ($msg);
            $self->{session} = 0;
            return { ok => $fail, msg => $msg };
        }
        else {
            my $msg = "CUSD message has unknown response type \"$response_type\"";
            $self->{log}->DEBUG ($msg);
            $self->{session} = 0;
            return { ok => $fail, msg => $msg };
        }
        # Only reached if USSD response type is 0 or 1
        return { ok => $success, msg => $self->_interpret_ussd_data ($response, $dcs) };
    }
    else {
        $self->{log}->DEBUG ("USSD query failed, error: " . $result->{description});
        return { ok => $fail, msg => $result->{description} };
    }
}


########################################################################
# Method:   cancel_ussd_session
# Args:     None.
# Returns:  Hashref 
#           Key 'ok':   $success if USSD query successfully transmitted
#                       and answer received
#                       $fail if USSD query aborted or not able to send
#           Key 'msg':  Error message or USSD query result, in accordance
#                       to the value of 'ok'.
sub cancel_ussd_session {
    my ($self) = @_;

    $self->{log}->DEBUG ('Trying to cancel USSD session');
    my $result = $self->{modem}->send_command ( "AT+CUSD=2\r", 'wait_for_OK' );
    if ( $result->{ok} ) {
        my $msg = 'USSD cancel request successful';
        $self->{log}->DEBUG ($msg);
        return { ok => $success, msg => $msg };
    }
    my $msg = 'No USSD session to cancel.';
    $self->{log}->DEBUG ($msg);
    return { ok => $fail, msg => $msg };
}


########################################################################
# Function: _interpret_ussd_data
# Args:     $response   -   The USSD string response
#           $encoding   -   The USSD encoding (dcs)
# Returns:  String containint the USSD response in clear text
sub _interpret_ussd_data {
    my ($self, $response, $enc) = @_;

    if ( ! defined $enc ) {
        $self->{log}->DEBUG ("CUSD message has no encoding, interpreting as cleartext");
        return $response;
    }
    my $dcs = GSMUSSD::DCS->new($enc);
    my $code= GSMUSSD::Code->new();

    if ( $dcs->is_default_alphabet() ) {
        $self->{log}->DEBUG ("Encoding \"$enc\" says response is in default alphabet");
        if ( $self->{use_cleartext} ) {
            $self->{log}->DEBUG ("Modem uses cleartext, interpreting message as cleartext");
            return $response;
        }
        elsif ( $enc == 0 ) {
            return $code->decode_8bit( $response );
        }
        elsif ( $enc == 15 ) {
            return decode( 'gsm0338', $code->decode_7bit( $response ) );
        }
        else {
            $self->{log}->DEBUG ("CUSD message has unknown encoding \"$enc\", using 0");
            return $code->decode_8bit( $response );
        }
        # NOTREACHED
    }
    elsif ( $dcs->is_ucs2() ) {
        $self->{log}->DEBUG ("Encoding \"$enc\" says response is in UCS2-BE");
        return decode ('UCS-2BE', $code->decode_8bit ($response));
    }
    elsif ( $dcs->is_8bit() ) {
        $self->{log}->DEBUG ("Encoding \"$enc\" says response is in 8bit");
        return $code->decode_8bit ($response);
    }
    else {
        $self->{log}->DEBUG ("CUSD message has unknown encoding \"$enc\", using 0");
        return $code->decode_8bit( $response );
    }
    # NOTREACHED
}


########################################################################
# Method:   ussd_query_cmd
# Args:     The USSD-Query to send 
# Returns:  An AT+CUSD command with properly encoded args
sub ussd_query_cmd {
	my ($self, $ussd_cmd)           = @_;

	my $result_code_presentation    = '1';      # Enable result code presentation
	my $dcs                         = '15';     # Default alphabet, 7bit
	my $ussd_string;

    if ( $self->{modem_uses_cleartext} ) {
        $ussd_string = $ussd_cmd;
    }
    else {
        my $code = GSMUSSD::Code->new();
        $ussd_string = $code->encode_7bit( encode('gsm0338', $ussd_cmd) );
    }
	return sprintf 'AT+CUSD=%s,"%s",%s', $result_code_presentation, $ussd_string, $dcs;
}


1;

########################################################################
__END__

=head1 NAME

GSMUSSD::UssdQuery

=head1 SYNOPSYS

 use GSMUSSD::UssdQuery;

 my $code = GSMUSSD::Code->new();
 my $ussd = $code->encode_7bit('*100#');
 my $answer = $code->decode_7bit ($e160_ussd_response);

=head1 DESCRIPTION

=head1 AUTHOR

Jochen Gruse, L<mailto:jochen@zum-quadrat.de>

