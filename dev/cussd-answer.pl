#!/usr/bin/perl
# vim: set expandtab sw=4 ts=4 ai nu: 

use strict;
use warnings;

# Wie man hier sieht, sind die Antwortdaten im Format 8 Bit pro Zeichen abgesendet.
# Das erste Zeichen ist 0x80, hat also das MSB gesetzt - das könnte das Zeichen 
# sein, welches anzeigt, dass die folgenden Daten 8bittig sind?
# Hier handelt es sich genau genommen um eine Fehlermeldung. Bei einer normalen
# Statusmeldung beginnt die Meldung mit 0x20 statt 0x80 - hat das eine Aussage?
# Generell scheint das erste Byte eher einen Status zu tragen als Textinhalt
# zu sein.
# Oder auch nicht! Ein Test im Handy hat ergeben, dass das erste Zeichen der
# Meldung auch im Handy als Space dargestellt wird! Außerdem haben andere Meldungen
# (falsches CashCode-Format, erfolgreiche Aufladung, Aufladeversuch mit 
# benutztem CashCode) kein spezielles Zeichen vorneweg, sondern beginnen
# eindeutig direkt mit der Meldung.

my $pdu_data    = @ARGV != 0?
                    $ARGV[0] : 
                    '805369652073696E64207A75206469657365722046756E6B74696F6E206E6963687420626572656368746967742E';

my $output      = '';

while ( $pdu_data =~ m/(..)/g ) {
	$output .= chr hex $1;
}

print $output, $/;

exit 0;
