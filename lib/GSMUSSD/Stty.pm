#!/usr/bin/perl

use strict;
use warnings;

package GSMUSSD::Stty;

use POSIX qw/:termios_h/;

use GSMUSSD::Loggit;


sub new {
	my ($class, $filehandle) = @_;
	my $self = {
		filehandle	=> $filehandle,
		savestate	=> undef,
		log		=> GSMUSSD::Loggit->new(),
	};
	bless $self, $class;
	return $self;
}


########################################################################
# Function: save
# Args:     $interface   -   The file handle to remember termios values of
# Returns:  Hashref containing the termios values found
#           undef in case of errors
sub save {
    my ($self) = @_;
    
    $self->{log}->DEBUG ("Saving serial state");

    my $termios = POSIX::Termios->new();

    $termios->getattr(fileno($self->{filehandle}));

    $self->{savestate}->{cflag}          = $termios->getcflag();
    $self->{savestate}->{iflag}          = $termios->getiflag();
    $self->{savestate}->{lflag}          = $termios->getlflag();
    $self->{savestate}->{oflag}          = $termios->getoflag();
    $self->{savestate}->{ispeed}         = $termios->getispeed();
    $self->{savestate}->{ospeed}         = $termios->getospeed();
    $self->{savestate}->{cchars}{'INTR'} = $termios->getcc(VINTR);
    $self->{savestate}->{cchars}{'QUIT'} = $termios->getcc(VQUIT);
    $self->{savestate}->{cchars}{'ERASE'}= $termios->getcc(VERASE);
    $self->{savestate}->{cchars}{'KILL'} = $termios->getcc(VKILL);
    $self->{savestate}->{cchars}{'EOF'}  = $termios->getcc(VEOF);
    $self->{savestate}->{cchars}{'TIME'} = $termios->getcc(VTIME);
    $self->{savestate}->{cchars}{'MIN'}  = $termios->getcc(VMIN);
    $self->{savestate}->{cchars}{'START'}= $termios->getcc(VSTART);
    $self->{savestate}->{cchars}{'STOP'} = $termios->getcc(VSTOP);
    $self->{savestate}->{cchars}{'SUSP'} = $termios->getcc(VSUSP);
    $self->{savestate}->{cchars}{'EOL'}  = $termios->getcc(VEOL);

    return $self;
}


########################################################################
# Function: restore
# Args:     $interface      -   The file handle to restore termios values for
#           $termdata       -   Hashref (return value of save_serial_opts)
# Returns:  1               -   State successfully set
#           0               -   State could not be restored
sub restore {
    my ($self) = @_;
    
    $self->{log}->DEBUG ("Restore serial state");

    my $termios = POSIX::Termios->new();

    $termios->setcflag( $self->{savestate}->{cflag} );
    $termios->setiflag( $self->{savestate}->{iflag} );
    $termios->setlflag( $self->{savestate}->{lflag} );
    $termios->setoflag( $self->{savestate}->{oflag} );
    $termios->setispeed( $self->{savestate}->{ispeed} );
    $termios->setospeed( $self->{savestate}->{ospeed} );
    $termios->setcc( VINTR, $self->{savestate}->{cchars}{'INTR'} );
    $termios->setcc( VQUIT, $self->{savestate}->{cchars}{'QUIT'} );
    $termios->setcc( VERASE,$self->{savestate}->{cchars}{'ERASE'});
    $termios->setcc( VKILL, $self->{savestate}->{cchars}{'KILL'} );
    $termios->setcc( VEOF,  $self->{savestate}->{cchars}{'EOF'}  );
    $termios->setcc( VTIME, $self->{savestate}->{cchars}{'TIME'} );
    $termios->setcc( VMIN,  $self->{savestate}->{cchars}{'MIN'}  );
    $termios->setcc( VSTART,$self->{savestate}->{cchars}{'START'});
    $termios->setcc( VSTOP, $self->{savestate}->{cchars}{'STOP'} );
    $termios->setcc( VSUSP, $self->{savestate}->{cchars}{'SUSP'} );
    $termios->setcc( VEOL,  $self->{savestate}->{cchars}{'EOL'}  );

    my $result = $termios->setattr(fileno($self->{filehandle}));
    if ( ! defined $result ) {
        $self->{log}->DEBUG ("Could not restore serial state");
        return undef;
    }
    return $self;
}


########################################################################
# Function: set_raw_noecho
# Args:     $interface      -   The file handle to set termios values for
# Returns:  1               -   Success
#           0               -   Failure
sub set_raw_noecho {
    my ($self) = @_;
    
    $self->{log}->DEBUG ("Setting serial state");

    my $termios = POSIX::Termios->new();
    $termios->getattr(fileno($self->{filehandle}));

    $termios->setcflag( CS8 | HUPCL | CREAD | CLOCAL );
    $termios->setiflag( 0 ); # Nothing on!
    $termios->setlflag( 0 ); # Nothing on!
    $termios->setoflag( 0 );
    # $termios->setispeed( $termdata->{ispeed} ); #Autobaud
    # $termios->setospeed( $termdata->{ospeed} ); #Autobaud

    my $result = $termios->setattr(fileno($self->{filehandle}));
    if ( ! defined $result ) {
        $self->{log}->DEBUG ('Could not set raw/noecho');
        return undef;
    }
    return $self;
}

1;
