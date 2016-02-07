#!/usr/bin/perl -w

use lib '/Users/dws/checkouts/open/deb-osagchrome-siteshow/chrome-siteshow/lib';

use 5.014;
use Log::Any qw($log);
use Log::Any::Adapter;
use Log::Dispatch;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Protocol::WebSocket::Handshake::Server;
use Protocol::WebSocket::Frame;

my $tcp_server;
my $chromi_socket;
my $chromi_connected;

sub start_server
{
    $tcp_server = AnyEvent::Socket::tcp_server undef, 7441, sub {
        my ($clsock, $host, $port) = @_;
     
        my $hs    = Protocol::WebSocket::Handshake::Server->new;
        my $frame = Protocol::WebSocket::Frame->new;
     
        $chromi_socket = AnyEvent::Handle->new(fh => $clsock);

        $chromi_socket->on_error(
            sub {
                my ($handle, $fatal, $message);
                if($fatal) {
                    $log->error("socket fatal error: $message");
                    $chromi_connected = 0;
                }
                else {
                    $log->warning("socket error: $message");
                }
            }
        );

        $chromi_socket->on_eof(
            sub {
                $chromi_connected = 0;
            }
        );
     
        $chromi_socket->on_read(
            sub {
                my $socket = shift;
     
                my $chunk = $socket->{rbuf};
                $socket->{rbuf} = undef;
     
                # Handshake
                if (!$hs->is_done) {
                    $hs->parse($chunk);
                    if ($hs->is_done) {
                        $socket->push_write($hs->to_string);
                        $chromi_connected = 1;
                    }
                }
     
                $chromi_connected or return;

                # Post-Handshake
                $frame->append($chunk);
     
                while (my $message = $frame->next) {
                    if($message =~ /^Chromi (\d+) (\w+) (.*)$/) {
                        my ($id, $status, $reply) = ($1, $2, $3);
                        use DDP;
                        say "$id $status $reply";
                        #if($self->{callbacks}{$id}) {
                        #    $reply = uri_unescape($reply);
                        #    if($reply =~ /^\[(.*)\]$/s) {
                        #        &{$self->{callbacks}{$id}}($status, decode_json($1));
                        #    }
                        #    else {
                        #        die "error: $reply\n";
                        #    }
                        #    delete $self->{callbacks}{$id};
                        #}
                    }
                }
            }
        );
    };
}

sub main()
{
    my $ld_log = Log::Dispatch->new(
       outputs => [
	    [ 'Syslog', min_level => 'info', ident  => 'chrome-siteshow' ],
	    [ 'Screen', min_level => 'debug', newline => 1 ],
	]
    );
    Log::Any::Adapter->set( 'Dispatch', dispatcher => $ld_log );

    $log->info("starting up");
    my $cv = AnyEvent->condvar;
    start_server();
    $cv->wait();
}

main;
