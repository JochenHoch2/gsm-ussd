#!/usr/bin/perl

use strict;
use warnings;

package GSMUSSD::Loggit;

my $self = undef;

sub new {
	my $class = shift;
	if ( ! defined $self) {
		$self = {};
		bless $self, $class;
	}
	return $self;
}

sub DEBUG {
	my ($self, @msgs) = @_;
	my ($callerpackage, undef, undef) = caller;
	print STDERR "[DEBUG][$callerpackage] " . join (' ', @msgs), $/;
}

1;
