#!/usr/bin/perl
########################################################################
# vim: set expandtab sw=4 ts=4 ai nu: 
########################################################################
# Module:           GSMUSSD::Loggit
# Documentation:    POD at __END__
########################################################################

package GSMUSSD::Loggit;

use strict;
use warnings;


########################################################################
# Class variables
########################################################################
my $self = undef;


########################################################################
# Function: new
# Type:     Constructor
# Args:     $really_log - If false, no debugging output will be generated
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


########################################################################
# Function: really_log
# Type:     Getter/Setter
# Args:     $really_log?    - If false, no debugging output will be generated
sub really_log {
	my ($self, $really_log) = @_;
	if ( defined $really_log) {
		$self->{really_log} = $really_log;
	}
	return $self->{really_log};
}


########################################################################
# Function: DEBUG
# Type:     Instance
# Args:     Strings - Messages to print to STDERR
sub DEBUG {
	my ($self, @msgs) = @_;

	return unless $self->really_log();

	my ($callerpackage, undef, undef) = caller;
	print STDERR "[DEBUG][$callerpackage] " . join (' ', @msgs), $/;
}


1;

__END__

=head1 NAME

GSMUSSD::Loggit

=head1 SYNOPSYS

 use GSMUSSD::Loggit;

 my $log = GSMUSSD::Loggit->new( 1 );
 $log->DEBUG( "IO error:", $! );

=head1 DESCRIPTION

=head1 AUTHOR

Jochen Gruse, L<mailto:jochen@zum-quadrat.de>

