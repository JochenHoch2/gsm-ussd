#!/usr/bin/perl

use strict;
use warnings;

package GSMUSSD::Loggit;

sub new {
	my $class = shift;
	my $self = {};
	bless $self, $class;
	return $self;
}

sub DEBUG {
	my ($self, @msgs) = @_;
	print STDERR '[DEBUG] ' . join (' ', @msgs), $/;
}

1;
