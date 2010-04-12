#!/usr/bin/perl

# Dieses Skript war der erste Ansaatz, die CUSD-Meldungen 
# zu verstehen. Abgelöst von gsm.pl

use strict;
use warnings;

# Eine echte PDU sieht anders aus! Hier dreht es sich nur um die 
# Daten, die eine PDU mitbringt. Dort ist normalerweise auch noch
# ein führendes Byte dabei, welches anzeigt, wieviele Zeichen im 
# Userdata-Feld kommen (in 7Bit-kodierten Zeichen!).

my $pdu_data		= @ARGV != 0? $ARGV[0] : '54C5830460';
# my $pdu_data		= 'D4F29C4E2FE3E9BA4D19';
# my $pdu_data		= 'AA182C3602';

my $bits_in_buffer	= 0;
my $bitbuffer		= 0;
my $output		= '';

my @gsm_char_table = (
	'@', '£', '$', '¥', 'è', 'é', 'ù', 'ì', 'ò', 'Ç', "\012",    'Ø', 'ø', "\015", 'Å', 'å', 
	'Δ', '_', 'Φ', 'Γ', 'Λ', 'Ω', 'Π', 'Ψ', 'Σ', 'Θ',    'Ξ', "\033", 'Æ',    'æ', 'ß', 'É', 
	' ', '!', '"', '#', '¤', '%', '&', "'", '(', ')',    '*',    '+', ',',    '-', '.', '/', 
	'0', '1', '2', '3', '4', '5', '6', '7', '8', '9',    ':',    ';', '<',    '=', '>', '?', 
	'¡', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I',    'J',    'K', 'L',    'M', 'N', 'O', 
	'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y',    'Z',    'Ä', 'Ö',    'Ñ', 'Ü', '§', 
	'¿', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i',    'j',    'k', 'l',    'm', 'n', 'o', 
	'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y',    'z',    'ä', 'ö',    'ñ', 'ü', 'à', 
);

my %gsm_char2val;
for (my $i = 0; $i < @gsm_char_table; ++$i) {
	$gsm_char2val{$gsm_char_table[$i]} = $i;
}

while ($pdu_data =~ /(..)/g) {

	# 8 Bits holen
	my $hex = hex($1);

	# Um die Anzahl der buffer vorhandenen Bits linksshiften
	$hex = $hex << $bits_in_buffer;

	# Neue Bits in den Buffer hinein-ORen
	$bitbuffer = $bitbuffer | $hex;
	$bits_in_buffer += 8;

	# Solange wie komplette Septette vorhanden sind, diese
	# entnehmen und anhand der Tabelle in Zeichen umsetzen.
	while ( $bits_in_buffer >= 7 ) {
		# 7 Bits entnehmen
		my $seven_bits = $bitbuffer & 0x7F;
		$bitbuffer = $bitbuffer >> 7;
		$output .=  _get_gsm_char($seven_bits);
		printf "%s = %02X\n", _get_gsm_char($seven_bits),$seven_bits;
		$bits_in_buffer -= 7;
	}
}

print "$output\n";

exit 0;

# Dies müsste noch weiter angepasst werden: Nach ESC folgt ein Zeichen
# aus einem Erweiterungzeichensatz!
sub _get_gsm_char {
	my ($char_value) = @_;
	return $gsm_char_table[$char_value];
}

__END__
	
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
