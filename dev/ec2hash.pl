#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;

my %hash = ();

while (<>) {
	chomp;
	if ( m/^(CM[SE] ERROR): (\d+)\s+(.*)/ ) {
		$hash{$1}{$2} = $3;
	}
}

print Dumper ( \%hash );

exit 0;
