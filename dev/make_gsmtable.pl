#!/usr/bin/perl
########################################################################

# Dies war ein erster Ansatz, um aus einer im Web gefundenen Tabelle
# des GSM-Zeichencodes (genaue Bezeichnung unbekannt) ein Perl-Array
# zu erzeugen. 

# Probleme:
# * wie unten angeführt sind Nacharbeiten notwendig.
# * Es wird nur die Standard-Tabelle erzeugt, es gibt zusätzlich
#   eine weitere Tabelle mit Sonderzeichen wie €, [, ], \.

use strict;
use warnings;

# GSM-Zeichnsatztabelle im Perl-Format erstellen.

# Es sind Nacharbeiten an der ausgegebenen Tabelle nötig:
# * ¹ steht für ein LF
# * ² steht für ein CR
# * ³ steht für ein ESC
# * Das ' muss in "" eingeschlossen werden.

my $line = <DATA>;	# Titelzeile ueberlesen
my $line_counter = 0;
my @char_table = ();

while ($line = <DATA>) {
	chomp $line;
	my @chars = split /\t+/, $line;
	shift @chars;			# Reihenmarkierung ueberlesen
	$char_table[$line_counter] = \@chars;
	$line_counter++;
}

print <<'EOF';
	my @gsm_char_table = (
EOF

while ( @{$char_table[0]} > 0 ) {
	my $output = '';
	foreach $line (@char_table) {
		$output .= "'" . shift(@$line) . "', ";
	}
	print "\t\t$output\n";
}

print <<'EOF';
	);
EOF

exit 0;
__DATA__
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
0x0A	¹	Ξ	*	:	J	Z	j	z
0x0B	Ø	³	+	;	K	Ä	k	ä
0x0C	ø	Æ	,	<	L	Ö	l	ö
0x0D	²	æ	-	=	M	Ñ	m	ñ
0x0E	Å	ß	.	>	N	Ü	n	ü
0x0F	å	É	/	?	O	§	o	à
