#!/usr/bin/perl
########################################################################
# vim: set expandtab sw=4 ts=4 ai nu: 
########################################################################
# Module:           GSMUSSD::NetworkErrors
# Documentation:    POD at __END__
########################################################################

package GSMUSSD::NetworkErrors;

use strict;
use warnings;

########################################################################
# Class variables
########################################################################

# GSM error codes found at 
# http://www.activexperts.com/xmstoolkit/sms/gsmerrorcodes/
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


########################################################################
# Method:   new
# Type:     Constructor
# Args:     None
sub new {
    my ($class) = @_;

    my $self = { };
    bless $self, $class;
    return $self;
}


########################################################################
# Method:   get_cms_error
# Args:     $error_number - the service error number to translate
#           If the error number is found not to be a unsigned integer,
#           it it returned as is - we were probably given a clear
#           text error message.
# Returns:  The error message corresponding to the error number
sub get_cms_error {
    my ($self, $error_number) = @_;
    
    if ( $error_number !~ /^\d+$/ ) {
        # We have probably been given an already readable error message.
        # The E160 is strange: Some error messages are english, some
        # are plain numbers!
        return $error_number;
    }
    elsif ( exists $gsm_error{'+CMS ERROR'}{$error_number} ) {
        # Translate the number into message
        return $gsm_error{'+CMS ERROR'}{$error_number} ;
    }
    # Number not found
    return 'No error description available';
}


########################################################################
# Method:   get_cme_error
# Args:     $error_number - the equipment error number to translate
#           If the error number is found not to be a unsigned integer,
#           it it returned as is - we were probably given a clear
#           text error message.
# Returns:  The error message corresponding to the error number
sub get_cme_error {
    my ($self, $error_number) = @_;
    
    if ( $error_number !~ /^\d+$/ ) {
        # We have probably been given an already readable error message.
        # The E160 is strange: Some error messages are english, some
        # are plain numbers!
        return $error_number;
    }
    elsif ( exists $gsm_error{'+CME ERROR'}{$error_number} ) {
        # Translate the number into message
        return $gsm_error{'+CME ERROR'}{$error_number} ;
    }
    # Number not found
    return 'No error description available';
}


1;

__END__

=head1 NAME

GSMUSSD::NetworkErrors

=head1 SYNOPSYS

 use GSMUSSD::NetworkErrors;

 my $err    = GSMUSSD::NetworkErrors->new();
 my $cmeerr = $err->get_cme_error( 100 );
 my $cmserr = $err->get_cms_error( 100 );

=head1 DESCRIPTION

=head1 AUTHOR

Jochen Gruse, L<mailto:jochen@zum-quadrat.de>
