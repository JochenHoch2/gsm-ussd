#!/usr/bin/perl

package GSMUSSD::Lockfile;

use strict;
use warnings;

use Fcntl;

use GSMUSSD::Loggit;


sub new {
	my ($class, $device) = @_;
	my $self = {
		device		=> $device,
		lockfile	=> undef,
		locked		=> 0,
		log		=> GSMUSSD::Loggit->new(),
	};
	bless $self, $class;
	return $self;
}


sub DESTROY {
	my ($self) = @_;
	
	if ($self->is_locked() ) {
		$self->release();
	}
}

sub device {
	my ($self, $device) = @_;
	
	if ( defined $device ) {
		if ( $self->is_locked() ) {
			$self->release();
		}
		$self->{device} = $device;
	}
	return $self->{device};
}


sub lockfile {
	my ($self) = @_;
	
	return $self->{lockfile};
}


sub is_locked {
	my ($self) = @_;

	return $self->{locked};
}

########################################################################
# Function: lock
# Args:     
# Returns:  
sub lock {
    my ($self) = @_;

  return 1 if $self->is_locked();

    my $lock_basedir    = '/var/lock';
    my ($lock_basename) = $self->device() =~ m#/([^/]*)$#;
    if ( ! defined $lock_basename || $lock_basename eq '' ) {
        $self->{log}->DEBUG("Can't find lock filename for \"$self->{device}\"");
        return 0;
    }
    $self->{lockfile} = $lock_basedir . '/LCK..' . $lock_basename;
    my $lock_handle;
    if ( ! sysopen $lock_handle, $self->{lockfile}, O_CREAT|O_WRONLY|O_EXCL, 0644 ) {
        $self->{log}->DEBUG ("Can't get lockfile $self->{lockfile} - probably already in use!\n");
        return 0;
    }
    print $lock_handle "$$\n";
    close $lock_handle;
    $self->{locked} = 1;
    $self->{log}->DEBUG ("Lock $self->{lockfile} set");
    return 1;
}


########################################################################
# Function: release
# Args:     
# Returns:  Nothing.
sub release {
    my ($self) = @_;

    if ( ! -f $self->{lockfile} ) {
        $self->{log}->DEBUG ("Lock file \"$self->{lockfile}\" doesn't exist or is not a normal file!");
        return 0;
    }
    if ( ! unlink $self->{lockfile} ) {
        $self->{log}->DEBUG ("Can't remove lock file \"$self->{lockfile}\": $!");
	return 0;
    }
    $self->{log}->DEBUG ("Lock $self->{lockfile} released");
    $self->{locked}	= 0;
    $self->{lockfile}	= undef;
    return 1;
}

1;
