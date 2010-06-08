#!/usr/bin/perl
########################################################################
# vim: set expandtab sw=4 ts=4 ai nu: 
########################################################################
# Class:            GSMUSSD::DCS
# Documentation:    See POD at __END__
########################################################################

package GSMUSSD::DCS;

use strict;
use warnings;

use Carp;


########################################################################
# Method:   new
# Type:     Constructor
# Args:     The DCS value received by an unsolicited USSD answer
sub new {
	my $class = shift;
	my $dcs = shift;
	
	if ( ! defined $dcs ) {
		carp 'No DCS given';
	}

	my $self = { };
	bless $self, $class;
	$self->dcs($dcs);
	return $self;
}

########################################################################
# Method:   dcs
# Type:     Instance
# Args:     $dcs: New DCS value to check
# Returns:  DCS value
sub dcs {
	my ($self, $dcs) = @_;
	if ( defined $dcs ) {
		$self->{dcs} = $dcs;
	}
	return $self->{dcs};
}


#######################################################################
# Method:   is_default_alphabet
# Args:     $enc    - the USSD dcs
# Returns:  1   - dcs indicates default alpabet
#           0   - dcs does not indicate default alphabet
sub is_default_alphabet {
    my ($self) = @_;

    if ( ! $self->_bit_is_set (6) && ! $self->_bit_is_set (7) ) {
        return 1;
    }
    if (     $self->_bit_is_set(6)
        && ! $self->_bit_is_set (7)
        && ! $self->_bit_is_set (2)
        && ! $self->_bit_is_set (3)
    ) {
        return 1;
    }
    return 0;
}


#######################################################################
# Method:   is_ucs2
# Args:     $enc    - the USSD dcs
# Returns:  1   - dcs indicates UCS2-BE
#           0   - dcs does not indicate UCS2-BE
sub is_ucs2 {
    my ($self) = @_;

    if (     $self->_bit_is_set (6)
        && ! $self->_bit_is_set (7)
        && ! $self->_bit_is_set (2)
        &&   $self->_bit_is_set (3)
    ) {
        return 1;
    }
    return 0;
}


#######################################################################
# Method:   is_8bit
# Args:     $enc    - the USSD dcs
# Returns:  1   - dcs indicates 8bit
#           0   - dcs does not indicate 8bit
sub is_8bit {
    my ($self) = @_;

    if (     $self->_bit_is_set (6)
        && ! $self->_bit_is_set (7)
        &&   $self->_bit_is_set (2)
        && ! $self->_bit_is_set (3)
    ) {
        return 1;
    }
    return 0;
}


########################################################################
# Method:   _bit_is_set
# Args:     $bit - Number of the bit to test
#           $val - Value to test bit $bit against
# Returns:  1   - Bit is set to 1
#           0   - Bit is set to 0
sub _bit_is_set {
    my ($self, $bit) = @_;
    return $self->dcs() & ( 2 ** $bit );
}

1;

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

