#!/usr/bin/perl
# vim: set expandtab sw=4 ts=4 ai nu: 
########################################################################

use strict;
use warnings;

use Encode qw/encode decode/;

########################################################################
# MAIN
########################################################################

binmode (STDOUT, ':utf8');

my $message = @ARGV == 0? 'AA182C3602' : $ARGV[0];

my $nachricht = decode_text($message);
print $nachricht, $/;

exit 0;

########################################################################
# Subs
########################################################################

sub hexstring_to_gsm0338 {
	return pack ("H*", $_[0]);
}

sub gsm0338_to_string {
	return decode ('gsm0338', $_[0]);
}

########################################################################
# Function: encode_text
# Args:     A string concisting of legal GSM chars.
# Returns:  A hex string, encoding the given string as a prtintable
#           representation of the seven bit GSM chars packed into
#           bytes.
sub encode_text {
	my ($text)              = @_;
	my @gsm_values	        = text_to_bytes($text);
	my @packed_gsm_values	= _gsm_pack(@gsm_values);
	return	            	bytes_to_hexstring(@packed_gsm_values);
}

########################################################################
# Function: decode_text
# Args:     A hex string of GSM packed values corresponding to GSM
#           chars.
# Returns:  A human readable version the argument.
sub decode_text {
	my ($hex_string)    	= @_;
	my $packed_gsm_values	= hexstring_to_gsm0338($hex_string);
	my $gsm_values	        = _gsm_unpack($packed_gsm_values);
	return	            	gsm0338_to_string($gsm_values);
}

########################################################################
# Function: _bit_stream     Argl, rename this!
# Args:     $count_bits_in  Number of bits per arg list element
#           $count_bits_out Number of bits per result list element
#           $bit_values_in  List of int values, each with $count_bits_in
#                           significant bits
# Returns:  List of int values, each with $count_bits_out significant
#           bits. From a "bit stream" point of view, nothing is changed,
#           only the number of bits per element in arg and result list
#           differ!
#
# This function is really only tested packing/unpacking 7 bit values to
# 8 bit values and vice versa. As this function uses bit operators,
# it'll probably work up to a maximum element size of 16 bits (both in
# and out). If you're running on an 64 bit platform, it might even work
# with elements up to 32 bits length. *Those are guesses, as I didn't
# test this!*

sub _bit_stream {
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
# Function: _gsm_unpack
sub _gsm_unpack {
	return _bit_stream (8,7, $_[0]);
}

########################################################################
# Function: _gsm_pack
sub _gsm_pack {
	return _bit_stream(7, 8, $_[0]);
}

