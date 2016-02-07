package AnyEvent::Chromi;

use strict;

use AnyEvent::Socket;
use AnyEvent::Handle;
 
use Protocol::WebSocket::Handshake::Server;
use Protocol::WebSocket::Frame;

use JSON::XS;
use URI::Escape;
use Log::Any qw($log);

sub new
{
    my $class = shift;
    my $self = {};
    bless $self, $class;

    $self->_start_server();

    return $self;
}

sub call
{
    my ($self, $method, $args, $cb) = @_;
    my $id = int(rand(100000000));
    my $msg = "chromi $id $method";
    if($args) {
        $msg .= " " . uri_escape(encode_json($args));
    }
    my $frame = Protocol::WebSocket::Frame->new($msg);
    if($cb) {
        $self->{callbacks}{$id} = $cb;
    }

    $self->{socket}->push_write($frame->to_bytes);
}

sub is_connected
{
    my ($self) = @_;
    return $self->{connected};
}

sub _start_server
{
    my ($self) = @_;
    $self->{tcp_server} = AnyEvent::Socket::tcp_server undef, 7441, sub {
        my ($clsock, $host, $port) = @_;
     
        my $hs    = Protocol::WebSocket::Handshake::Server->new;
        my $frame = Protocol::WebSocket::Frame->new;
     
        $self->{socket} = AnyEvent::Handle->new(fh => $clsock);

        $self->{socket}->on_error(
            sub {
                my ($handle, $fatal, $message);
                if($fatal) {
                    $log->error("socket fatal error: $message");
                    $self->{connected} = 0;
                }
                else {
                    $log->warning("socket error: $message");
                }
            }
        );

        $self->{socket}->on_eof(
            sub {
                $self->{connected} = 0;
            }
        );
     
        $self->{socket}->on_read(
            sub {
                my $socket = shift;
     
                my $chunk = $socket->{rbuf};
                $socket->{rbuf} = undef;
     
                # Handshake
                if (!$hs->is_done) {
                    $hs->parse($chunk);
                    if ($hs->is_done) {
                        $socket->push_write($hs->to_string);
                        $self->{connected} = 1;
                    }
                }
     
                $self->{connected} or return;

                # Post-Handshake
                $frame->append($chunk);
     
                while (my $message = $frame->next) {
                    if($message =~ /^Chromi (\d+) (\w+) (.*)$/) {
                        my ($id, $status, $reply) = ($1, $2, $3);
                        if($self->{callbacks}{$id}) {
                            $reply = uri_unescape($reply);
                            if($reply =~ /^\[(.*)\]$/s) {
                                &{$self->{callbacks}{$id}}($status, decode_json($1));
                            }
                            else {
                                die "error: $reply\n";
                            }
                            delete $self->{callbacks}{$id};
                        }
                    }
                }
            }
        );
    };
}

1;

=head1 NAME

AnyEvent::Chromi - Control Google Chrome from Perl

=head2 SYNOPSIS

    $chromi = AnyEvent::Chromi->new();

    # get windows and tabs list
    $chromi->call(
        'chrome.windows.getAll', [{ populate => Types::Serialiser::true }],
        sub {
            my ($status, $reply) = @_;
            $status eq 'done' or return;
            defined $reply and ref $reply eq 'ARRAY' or return;
            map { say "$_->{url}" } @{$reply->[0]{tabs}};
        }
    );

    # focus a tab
    $chromi->call(
        'chrome.tabs.update', [$tab_id, { active => Types::Serialiser::true }],
    );


=head2 DESCRIPTION
