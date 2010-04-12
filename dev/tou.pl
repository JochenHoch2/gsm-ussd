#!/usr/bin/perl

# Lektionen aus diesem Programm: s. POD

use strict;
use warnings;

my $modemport	= '/dev/ttyUSB1';
my $linecounter	= 0;
my $cmd		= 'AT';

open MODEM, '+<', $modemport
	or die "Kann Modemport $modemport nicht öffnen: $!";

print MODEM "$cmd\r";
while ($linecounter < 15) {
	my $line = <MODEM>;
	printf "%2d: %s\n", $linecounter, $line;
	++$linecounter;
}

close MODEM;

exit 0;

__END__

=head1 LEKTIONEN

Aus diesem Testprogramm lernten wir:

=over

=item *

Öffnet man das Modem, erhält man erst mal eine ganze Anzahl 
Zeilen aus dem Buffer. Sozusagen die letzten Meldungen, die das
Modem ansonsten noch nicht losgeworden ist.

=item *

Schließt und öffnet man das Modem direkt wieder, bekommt man die 
alten Meldungen nicht mehr zu Gesicht, sondern nur noch neue.
Diese schlagen ca. alle 1-2 Sekunden auf.

=item *

Ein spezielles Setzen der Kommunikationsparameter mit der
"seriellen Schnittstelle" ist nicht nötig!

Hier tut Forschung not: Wie sind die Parameter eigentlich?

=item *

Man kann dem Modem in seine Statusmeldungen unmotiviert 
AT-Kommandos dazwischenschmeissen. Die passenden OK-Meldungen
werden dann "irgendwann" später ausgegeben, wenn das Modem
seine letzten gebufferten Statusmeldungen losgeworden ist.

=item *

AT-Kommandos mit Carriage Return "\r" abschliessen! Ein reines
Newline "\n" versteht das Modem nicht. Abhilfe: In anderer Shell
picocom starten und ein paar mal Enter drücken. Man erhält ein
ERROR (letzte Abfrage "AT\n" wurde nicht verstanden, weil "\n"
kein Modem-Kommando ist), danach kann man noch mal "at<Enter>"
eintippen. Antwortet das Modem wieder mit OK, kann man sein 
Programm verbessern und wieder neu starten.

=back
