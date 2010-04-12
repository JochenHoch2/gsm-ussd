#!/usr/bin/perl

use strict;
use warnings;

use Device::Gsm;
use Data::Dumper;

my $huawei = new Device::Gsm ( port => '/dev/ttyUSB1', log => 'Syslog' );
die "Kann Modem nicht oeffnen" 
	unless ref $huawei;

my @messages = $huawei->messages();

$huawei->hangup();

exit 0;
