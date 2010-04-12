#!/usr/bin/perl

# Testprogramm, um den RE zu debuggen. Man sollte halt auch eine
# negierte Zeichenmenge nehmen, wenn man eine meint...

# Im Vergleich mit der auskommentierten Version kann man den 
# Fehler sehen: [\r\n] statt [^\r\n].

use strict;
use warnings;

 
# my $re = qr/^([\+\^]\w+):([\r\n]*)\r\n/;
my $re = qr/^([\+\^]\w+):([^\r\n]*)\r\n/;

my $line = "^RSSI:19\r\n";

if ($line =~ m/$re/im) {
	print "Treffer\n";
	print $&, $/;
}
else {
	print "Nix.\n";
}

exit 0;
