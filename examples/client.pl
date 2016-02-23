#!/usr/bin/perl -w

use lib '/Users/dws/checkouts/github/AnyEvent-Chromi/lib';
use 5.014;

use Log::Any qw($log);
use Log::Any::Adapter;
use Log::Dispatch;
use AnyEvent;
use AnyEvent::Chromi;

my $cv;

sub list_windows
{
    my ($chromi) = @_;

    $chromi->call(
        'chrome.windows.getAll', [{ populate => Types::Serialiser::true }],
        sub {
            my ($status, $reply) = @_;
            $status eq 'done' or return;
            defined $reply and ref $reply eq 'ARRAY' or return;
            map { say "$_->{url}" } @{$reply->[0]{tabs}};
        }
    );
}

sub main
{
    my $ld_log = Log::Dispatch->new(
       outputs => [
	    [ 'Syslog', min_level => 'info', ident  => 'chrome-siteshow' ],
	    [ 'Screen', min_level => 'debug', newline => 1 ],
	]
    );
    Log::Any::Adapter->set( 'Dispatch', dispatcher => $ld_log );

    $cv = AnyEvent->condvar;
    my $chromi = AnyEvent::Chromi->new(mode => 'client', on_connect => sub {
        list_windows($_[0]);
    });

    $cv->wait();
}

main;
