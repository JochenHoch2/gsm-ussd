#!/usr/bin/perl
########################################################################
# vim: set expandtab sw=4 ts=4 ai nu: 
########################################################################
# Module:           GSMUSSD::Code
# Documentation:    POD at __END__
########################################################################

package GSMUSSD::Code;

use strict;
use warnings;


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
# Method:   decode_8bit
# Type:     Instance
# Args:     String consisting of hex values
# Returns:  String containing the given values
sub decode_8bit {
	my ($self, $value) = @_;

	return pack( "H*", $value );
}


########################################################################
# Method:   encode_8bit
# Type:     Instance
# Args:     String 
# Returns:  Hexstring
sub encode_8bit {
	my ($self, $value) = @_;

	return uc( unpack( "H*", $value ) );
}


########################################################################
# Method:   decode_7bit
# Type:     Instance
# Args:     String to unpack 7 bit values from
# Returns:  String containing 7 bit values of the arg per byte
sub decode_7bit {
	my ($self, $value) = @_;

	return $self->_repack_bits( 8, 7, $self->decode_8bit ($value ) );
}


########################################################################
# Method:   encode_7bit
# Type:     Instance
# Args:     String of 7 bit values to pack (8 7 bit values into 7 eight
#           bit values)
# Returns:  String containing 7 bit values of the arg per character
sub encode_7bit {
	my ($self, $value) = @_;

	return $self->encode_8bit( $self->_repack_bits(7, 8, $value) );
}


########################################################################
# Method:   _repack_bits
# Type:     Instance
# Args:     $count_bits_in  Number of bits per arg list element
#           $count_bits_out Number of bits per result list element
#           $bit_values_in  String containing $count_bits_in bits per
#                           char
# Returns:  String containing $count_bits_out bits per char. From a "bit
#           stream" point of view, nothing is changed,
#           only the number of bits per char in arg and result string
#           differ!
#
# This method is really only tested packing/unpacking 7 bit values to
# 8 bit values and vice versa. As this function uses bit operators,
# it'll probably work up to a maximum element size of 16 bits (both in
# and out). If you're running on an 64 bit platform, it might even work
# with elements up to 32 bits length. *Those are guesses, as I didn't
# test this!*
sub _repack_bits {
    my ($self, $count_bits_in, $count_bits_out, $bit_values_in) = @_;

    my $bit_values_out	= '';
    my $bits_in_buffer	= 0;
    my $bitbuffer	= 0;
    my $bit_mask_out    = 2**$count_bits_out - 1;

    for (my $pos = 0; $pos < length ($bit_values_in); ++$pos) {
        my $in_bits = ord (substr($bit_values_in, $pos, 1));
		# Left shift the new bits as far as there are still
		# bits left in the buffer and OR them into the buffer.
		$bitbuffer = $bitbuffer | ( $in_bits << $bits_in_buffer);
		$bits_in_buffer += $count_bits_in;

		while ( $bits_in_buffer >= $count_bits_out ) {
			# Spit out the rightmost Bits
			$bit_values_out .= chr ( $bitbuffer & $bit_mask_out ) ;
			$bitbuffer = $bitbuffer >> $count_bits_out;
			$bits_in_buffer -= $count_bits_out;
		}	
	}
	# Spit out the remaining bits in buffer
	if ($count_bits_in < $count_bits_out && $bits_in_buffer > 0) {
            $bit_values_out .= chr ( $bitbuffer & $bit_mask_out ) ;
	}

	return $bit_values_out;
}

1;

__END__

=head1 NAME

GSMUSSD::Code

=head1 SYNOPSYS

 use GSMUSSD::Code;

 my $code = GSMUSSD::Code->new();
 my $ussd = $code->encode_7bit('*100#');
 my $answer = $code->decode_7bit ($e160_ussd_response);

=head1 DESCRIPTION

=head1 AUTHOR

Jochen Gruse, L<mailto:jochen@zum-quadrat.de>

