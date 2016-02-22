#!/usr/bin/perl -w

use lib '/Users/dws/checkouts/github/AnyEvent-Chromi/lib';

use Log::Any qw($log);
use Log::Any::Adapter;
use Log::Dispatch;
use AnyEvent;
use AnyEvent::Chromi;

sub main
{
    my $ld_log = Log::Dispatch->new(
       outputs => [
	    [ 'Syslog', min_level => 'info', ident  => 'chrome-siteshow' ],
	    [ 'Screen', min_level => 'debug', newline => 1 ],
	]
    );
    Log::Any::Adapter->set( 'Dispatch', dispatcher => $ld_log );

    my $cv = AnyEvent->condvar;
    my $chromi = AnyEvent::Chromi->new(mode => 'client');
    $cv->wait();
}

main;
