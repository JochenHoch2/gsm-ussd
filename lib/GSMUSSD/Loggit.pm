#!/usr/bin/perl

use strict;
use warnings;

package GSMUSSD::Loggit;

my $self = undef;

sub new {
	my ($class, $really_log) = @_;
	if ( ! defined $self) {
		$self = {
			really_log	=> $really_log 
		};
		bless $self, $class;
	}
	return $self;
}

sub really_log {
	my ($self, $really_log) = @_;
	if ( defined $really_log) {
		$self->{really_log} = $really_log;
	}
	return $self->{really_log};
}


sub DEBUG {
	my ($self, @msgs) = @_;

	return unless $self->really_log();

	my ($callerpackage, undef, undef) = caller;
	print STDERR "[DEBUG][$callerpackage] " . join (' ', @msgs), $/;
}

1;
