#!/usr/bin/perl
########################################################################
# vim: set expandtab sw=4 ts=4 ai nu: 
########################################################################
# Module:           GSMUSSD::Stty
# Documentation:    POD at __END__
########################################################################

package GSMUSSD::Stty;

use strict;
use warnings;

use POSIX qw/:termios_h/;
use GSMUSSD::Loggit;


########################################################################
# Method:   new
# Type:     Constructor
# Args:     $filehandle -   The filehandle to handle the termios settings
#                           for
sub new {
    my ($class, $filehandle) = @_;
    my $self = {
        filehandle  => $filehandle,
        filenum     => undef,
        savestate   => undef,
        log         => GSMUSSD::Loggit->new(),
    };
    bless $self, $class;
    return $self;
}


########################################################################
# Method:   save
# Args:     None
# Returns:  $self
sub save {
    my ($self) = @_;
    
    $self->{log}->DEBUG ("Saving serial state");

    my $termios = POSIX::Termios->new();

    $self->{filenum} = fileno ($self->{filehandle});
    $termios->getattr( $self->{filenum} );

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
# Method:   restore
# Args:     None
# Returns:  $self
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

    my $result = $termios->setattr( $self->{filenum} );
    if ( ! defined $result ) {
        $self->{log}->DEBUG ("Could not restore serial state");
        return undef;
    }
    return $self;
}


########################################################################
# Method:   set_raw_noecho
# Args:     None
# Returns:  $self
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
        return $self;
    }
    return $self;
}

1;

__END__

=head1 NAME

GSMUSSD::Stty

=head1 SYNOPSYS

 use GSMUSSD::Stty;

 my $stty = GSMUSSD::Stty->new( '/dev/ttyUSB1' );
 $stty->save();
 $stty->set_raw_noecho();
 ...
 $stty->restore();

=head1 DESCRIPTION

=head1 METHODS

=over

=item B<new>

=item B<save>

=item B<restore>

=item B<set_raw_noecho>

=back

=head1 AUTHOR

Jochen Gruse, L<mailto:jochen@zum-quadrat.de>

