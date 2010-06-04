#!/usr/bin/perl

package GSMUSSD::DCS;

use strict;
use warnings;

use Carp;

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

sub dcs {
	my ($self, $dcs) = @_;
	if ( defined $dcs ) {
		$self->{dcs} = $dcs;
	}
	return $self->{dcs};
}

#######################################################################
# Function: is_default_alphabet
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
# Function: is_ucs2
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
# Function: is_8bit
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
# Function: _bit_is_set
# Args:     $bit - Number of the bit to test
#           $val - Value to test bit $bit against
# Returns:  1   - Bit is set to 1
#           0   - Bit is set to 0
sub _bit_is_set {
    my ($self, $bit) = @_;
    return $self->dcs() & ( 2 ** $bit );
}

1;
