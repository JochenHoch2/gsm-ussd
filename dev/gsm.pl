#!/usr/bin/perl
########################################################################

# Dieses Skript diente soweit der Entwicklung der
# Codierungs-/Decodierungsroutinen.

# Die Subs wurden übernommen und werden nun in anderen Skripten weiter
# verbessert.

use strict;
use warnings;

my $cleartext		= @ARGV != 0? $ARGV[0] : '*100#';

my @gsm_std_char_table = (
	'@', '£', '$', '¥', 'è', 'é', 'ù', 'ì', 'ò', 'Ç', "\012",  'Ø', 'ø', "\015", 'Å', 'å', 
	'Δ', '_', 'Φ', 'Γ', 'Λ', 'Ω', 'Π', 'Ψ', 'Σ', 'Θ',    'Ξ', "\e", 'Æ',    'æ', 'ß', 'É', 
	' ', '!', '"', '#', '¤', '%', '&', "'", '(', ')',    '*',  '+', ',',    '-', '.', '/', 
	'0', '1', '2', '3', '4', '5', '6', '7', '8', '9',    ':',  ';', '<',    '=', '>', '?', 
	'¡', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I',    'J',  'K', 'L',    'M', 'N', 'O', 
	'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y',    'Z',  'Ä', 'Ö',    'Ñ', 'Ü', '§', 
	'¿', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i',    'j',  'k', 'l',    'm', 'n', 'o', 
	'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y',    'z',  'ä', 'ö',    'ñ', 'ü', 'à', 
);

my @gsm_ext_char_table = (
	 '', '', '', '',  '',  '', '', '',  '',  '', "\f",   '',  '',  '',  '',   '', 
	 '', '', '', '', '^',  '', '', '',  '',  '',   '', "\e",  '',  '',  '',   '', 
	 '', '', '', '',  '',  '', '', '', '{', '}',   '',   '',  '',  '',  '', '\\', 
	 '', '', '', '',  '',  '', '', '',  '',  '',   '',   '', '[', '~', ']',   '', 
	'|', '', '', '',  '',  '', '', '',  '',  '',   '',   '',  '',  '',  '',   '', 
	 '', '', '', '',  '',  '', '', '',  '',  '',   '',   '',  '',  '',  '',   '', 
	 '', '', '', '',  '', '€', '', '',  '',  '',   '',   '',  '',  '',  '',   '', 
	 '', '', '', '',  '',  '', '', '',  '',  '',   '',   '',  '',  '',  '',   '', 
);

my %gsm_std_char_map;
for (my $i = 0; $i < @gsm_std_char_table; ++$i) {
	$gsm_std_char_map{$gsm_std_char_table[$i]} = $i;
}

my %gsm_ext_char_map;
for (my $i = 0; $i < @gsm_ext_char_table; ++$i) {
	$gsm_ext_char_map{$gsm_ext_char_table[$i]} = $i;
}

print "$cleartext\n";

my $hex_string		= encode_text($cleartext);
print $hex_string, $/;
my $new_cleartext	= decode_text($hex_string);
print "$new_cleartext\n";
if ($cleartext eq $new_cleartext) {
	print "Erfolg, Konvertierung und Rekonvertierung ergeben Ursprungswert!\n";
}
else {
	print "Misserfolg, Konvertierung und Rekonvertierung ergeben was anderes als den Ursprungswert!\n";
}

exit 0;

########################################################################

sub encode_text {
	my ($text) 	= @_;
	my @gsm_values		= text_to_gsm_values($text);
	my @packed_gsm_values	= _gsm_pack(@gsm_values);
	return			bytes_to_hexstr(@packed_gsm_values);
}

sub decode_text {
	my ($hex_string)	= @_;
	my @packed_gsm_values	= pdu_to_gsm_values($hex_string);
	my @gsm_values		= _gsm_unpack(@packed_gsm_values);
	return			gsm_values_to_text(@gsm_values);
}

# 7-Bit-Werte in 8 Bit-Folge packen 
sub _gsm_pack {
	my @seven_bit_values = @_;

	my @eight_bit_values	= ();
	my $bits_in_buffer	= 0;
	my $bitbuffer		= 0;
	my $eight_bit_mask	= 0xFF;

	foreach my $seven_bits (@seven_bit_values) {
		# Die neuen Bits soweit linksshiften, wie noch Bits
		# im Buffer sind und mit dem Buffer ORen.
		# Die vorhandenen Bits um 7 Bits linksshiften
		$bitbuffer = $bitbuffer | ( $seven_bits << $bits_in_buffer);
		$bits_in_buffer += 7;

		if ( $bits_in_buffer >= 8 ) {
			# Die letzten 8 Bits ausspucken
			push @eight_bit_values, $bitbuffer & $eight_bit_mask;
			$bitbuffer = $bitbuffer >> 8;
			$bits_in_buffer -= 8;
		}	
	}
	if ($bits_in_buffer > 0) {
		push @eight_bit_values, $bitbuffer & $eight_bit_mask;
	}

	return @eight_bit_values;
}

########################################################################

# 8 Bit-Folge in Siebener-Bit-Werte auspacken
sub _gsm_unpack {
	my (@eight_bit_values)	= @_;
	my @seven_bit_values	= ();
	my $bits_in_buffer	= 0;
	my $bitbuffer		= 0;
	my $seven_bit_mask	= 0x7F;

	foreach my $eight_bits (@eight_bit_values) {
		# Um die Anzahl der buffer vorhandenen Bits linksshiften
		$eight_bits = $eight_bits << $bits_in_buffer;

		# Neue Bits in den Buffer hinein-ORen
		$bitbuffer = $bitbuffer | $eight_bits;
		$bits_in_buffer += 8;
		# Solange wie komplette Septette vorhanden sind, diese
		# entnehmen und anhand der Tabelle in Zeichen umsetzen.
		while ( $bits_in_buffer >= 7 ) {
			# 7 Bits entnehmen
			push @seven_bit_values, $bitbuffer & $seven_bit_mask;
			$bitbuffer = $bitbuffer >> 7;
			$bits_in_buffer -= 7;
		}
	}
	# Sollte ein Rest im Buffer stecken, sind das nur Füll-Nullen.
	return @seven_bit_values;
}

########################################################################

sub pdu_to_gsm_values {
	my ($pdu_data) = @_;
	my @packed_gsm_values;

	# TODO: Keine gute Idee, den String aufzubrauchen... 
	while (length $pdu_data > 1) {
		my $hexstring	= substr $pdu_data, 0, 2;
		$pdu_data	= substr $pdu_data, 2;
		push @packed_gsm_values, hex $hexstring;
	}
	return @packed_gsm_values;
}

########################################################################

sub text_to_gsm_values {
	my ($text)	= @_;
	my @gsm_values	= ();
	
	# TODO: Keine gute Idee, den String aufzubrauchen... 
	while (length $text > 0) {
		my $char	= substr $text, 0, 1;
		$text		= substr $text, 1;
		if ( exists $gsm_std_char_map{$char} ) {
			push @gsm_values, $gsm_std_char_map{$char};
		}
		elsif ( exists $gsm_ext_char_map{$char} ) {
			push @gsm_values, 0x1B, $gsm_ext_char_map{$char};
		}
		else {
			# Beschwerde: Zeichen nicht im GSM-Zeichensatz enthalten!
			die "Zeichen $char nicht im GSM-Zeichensatz";
		}
	}
	return @gsm_values;
}

########################################################################

sub gsm_values_to_text {
	my (@gsm_values)	= @_;
	my $text;
	
	my $use_ext_table	= 0;
	my $char;
	foreach my $gsm_value (@gsm_values) {
		if ( $gsm_value == 0x1B ) {
			$use_ext_table = 1;
			next;
		}
		if ( $use_ext_table == 0) {
			$char = $gsm_std_char_table[$gsm_value];
		}
		else {
			$char = $gsm_ext_char_table[$gsm_value];
			$use_ext_table = 0;
		}
		$text	.= $char;
	}
	return $text;
}

########################################################################

sub bytes_to_hexstr {
	my $format_string = "%02X" x scalar @_;
	return sprintf $format_string, @_;
}

########################################################################
__END__
Standard GSM-Zeichentabelle	
	0x00	0x10	0x20	0x30	0x40	0x50	0x60	0x70
0x00	@	Δ	 	0	¡	P	¿	p
0x01	£	_	!	1	A	Q	a	q
0x02	$	Φ	"	2	B	R	b	r
0x03	¥	Γ	#	3	C	S	c	s
0x04	è	Λ	¤	4	D	T	d	t
0x05	é	Ω	%	5	E	U	e	u
0x06	ù	Π	&	6	F	V	f	v
0x07	ì	Ψ	'	7	G	W	g	w
0x08	ò	Σ	(	8	H	X	h	x
0x09	Ç	Θ	)	9	I	Y	i	y
0x0A	LF	Ξ	*	:	J	Z	j	z
0x0B	Ø	ESC	+	;	K	Ä	k	ä
0x0C	ø	Æ	,	<	L	Ö	l	ö
0x0D	CR	æ	-	=	M	Ñ	m	ñ
0x0E	Å	ß	.	>	N	Ü	n	ü
0x0F	å	É	/	?	O	§	o	à

Erweiterte GSM-Zeichentabelle
	0x00	0x10	0x20	0x30	0x40	0x50	0x60	0x70
0x00					|			
0x01								
0x02								
0x03								
0x04		ˆ						
0x05							€	
0x06								
0x07								
0x08			{					
0x09			}					
0x0A	¹							
0x0B		²						
0x0C				[				
0x0D				˜				
0x0E				]				
0x0F			\					
