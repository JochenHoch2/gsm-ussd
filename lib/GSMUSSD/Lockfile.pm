#!/usr/bin/perl

package GSMUSSD::Lockfile;

use strict;
use warnings;

use Fcntl;
use GSMUSSD::Loggit;


########################################################################
# Method:   new
# Type:     Constructor
# Args:     $device - The serial interface to lock
# TODO:     Check device?
sub new {
	my ($class, $device) = @_;

	my $self = {
		device      => undef,
		lockfile    => undef,
		locked      => 0,
		log	        => GSMUSSD::Loggit->new(),
	};
	bless $self, $class;
    $self->device($device);
	return $self;
}


########################################################################
# Method:   DESTROY
# Type:     Destructor
# Args:     None
sub DESTROY {
	my ($self) = @_;
	
	if ($self->is_locked() ) {
		$self->release();
	}
}


########################################################################
# Method:   device
# Type:     Getter/Setter
# Args:     $device
# Returns:  The device (just set or old)
sub device {
	my ($self, $device) = @_;
	
	if ( defined $device ) {
        # Set
		if ( $self->is_locked() ) {
			$self->release();
		}
		$self->{device}     = $device;
        $self->{lockfile}   = $self->_get_lockfile_name();
	}
	return $self->{device};
}


########################################################################
# Method:   lockfile
# Type:     Getter
# Args:     None
# Returns:  The lockfile to set for $device
sub lockfile {
	my ($self) = @_;
	
	return $self->{lockfile};
}


########################################################################
# Method:   is_locked
# Type:     Getter
# Args:     None
# Returns:  Boolean - Lockfile set or unset
sub is_locked {
	my ($self) = @_;

	return $self->{locked};
}


########################################################################
# Method:   lock
# Args:     None
# Returns:  Boolean - lock successful or failed
sub lock {
    my ($self) = @_;

  return 1 if $self->is_locked();

    my $lock_handle;
    if ( ! sysopen $lock_handle, $self->lockfile(), O_CREAT|O_WRONLY|O_EXCL, 0644 ) {
        $self->{log}->DEBUG ($self->lockfile() . ": Can't set lockfile - probably already in use!");
        return 0;
    }
    print $lock_handle "$$\n";
    close $lock_handle;
    $self->{locked} = 1;
    $self->{log}->DEBUG ('Lock set: ', $self->lockfile() );
    return 1;
}


########################################################################
# Method:   release
# Args:     None
# Returns:  Boolean - Lock release successful or failed
sub release {
    my ($self) = @_;

    if ( ! -f $self->lockfile () ) {
        $self->{log}->DEBUG ($self->lockfile(), ': Lock file does not exist or is not a normal file!');
        return 0;
    }
    if ( ! unlink $self->{lockfile} ) {
        $self->{log}->DEBUG ($self->lockfile(), ": Cannot remove lock file: $!");
        return 0;
    }
    $self->{log}->DEBUG ("Lock $self->{lockfile} released");
    $self->{locked}     = 0;
    return 1;
}


########################################################################
# Method:   _get_lockfile_name
# Args:     None
# Returns:  String - The absolute lockfile name
sub _get_lockfile_name {
    my ($self) = @_;

    my $lock_basedir    = '/var/lock';
    my ($lock_basename) = $self->device() =~ m/\/([^\/]*)$/;
    if ( ! defined $lock_basename || $lock_basename eq '' ) {
        $self->{log}->DEBUG("Can't find lock filename for ", $self->device() );
        return undef;
    }
    return $lock_basedir . '/LCK..' . $lock_basename;
}

1;

__END__

=head1 NAME

GSMUSSD::Lockfile

=head1 SYNOPSYS

 use GSMUSSD::Lockfile;

 my $lock = GSMUSSD::Lockfile->new( $device );
 if ( $lockfile->lock() ) {
    print 'Lock achieved: ' . $lock->lockfile() . $/;
 }
 $lockfile->unlock();

=head1 DESCRIPTION

=head1 AUTHOR

Jochen Gruse, L<mailto:jochen@zum-quadrat.de>

