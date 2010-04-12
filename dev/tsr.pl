#!/usr/bin/perl

use strict;
use warnings;

my $modemport	= '/dev/ttyUSB1';
my $linecounter	= 0;
# my $cmd		= 'AT';
my $cmd		= 'ATI';
my $sleep	= 5;

open MODEM, '+<', $modemport
	or die "Kann Modemport $modemport nicht öffnen: $!";

print MODEM $cmd, "\015\012";

my $output	= '';
my $count_bytes	= 0;

while ($count_bytes < 1025 ) {
	my $success = sysread MODEM, my $byte, 1;
	if (!defined $success || $success == 0) {
		print STDERR "Abbruch: $!";
		last;
	}
	$output .= $byte;
	$count_bytes += $success;
}

print $output;

close MODEM;

exit 0;
