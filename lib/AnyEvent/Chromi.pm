package AnyEvent::Chromi;

use strict;

use AnyEvent::Socket;
use AnyEvent::Handle;
 
use Protocol::WebSocket::Handshake::Client;
use Protocol::WebSocket::Handshake::Server;
use Protocol::WebSocket::Frame;

use JSON::XS;
use URI::Escape;
use Log::Any qw($log);

sub new
{
    my ($class, %args) = @_;
    my $self = {};
    bless $self, $class;

    $self->{mode} = $args{mode} // 'server';
    $self->{on_connect} = $args{on_connect} if defined $args{on_connect};
    if($self->{mode} eq 'client') {
        $self->_start_client();
    }
    else {
        $self->_start_server();
    }

    return $self;
}

sub call
{
    my ($self, $method, $args, $cb) = @_;
    if(not $self->is_connected) {
        $log->warning("can't call $method: not connected");
        return;
    }
    $log->info("calling $method");
    my $id = int(rand(100000000));
    my $msg = "chromi $id $method";
    if($args) {
        $msg .= " " . uri_escape(encode_json($args));
    }
    my $frame = Protocol::WebSocket::Frame->new($msg);
    if($cb) {
        $self->{callbacks}{$id} = $cb;
    }
    $self->{handle}->push_write($frame->to_bytes);
}

sub is_connected
{
    my ($self) = @_;
    return $self->{connected};
}

sub _setup_connection
{
    my ($self, $fh) = @_;

    my $ws_handshake = $self->{mode} eq 'client' ? Protocol::WebSocket::Handshake::Client->new(url => 'ws://localhost') :
                                                   Protocol::WebSocket::Handshake::Server->new;
    my $ws_frame = Protocol::WebSocket::Frame->new;
    
    $self->{handle} = AnyEvent::Handle->new(fh => $fh);

    $self->{handle}->on_error(
        sub {
            my ($handle, $fatal, $message);
            if($fatal) {
                $log->error("connection fatal error: $message");
                $self->{connected} = 0;
            }
            else {
                $log->warning("connection error: $message");
            }
        }
    );

    $self->{handle}->on_eof( sub {
        $self->{connected} = 0;
        if($self->{mode} eq 'client') {
            $self->_client_schedule_reconnect();
        }
    });

    $self->{handle}->on_read( sub {
        my ($handle) = @_;
        my $chunk = $handle->{rbuf};
        $handle->{rbuf} = undef;
        
        # Handshake
        if (!$ws_handshake->is_done) {
            $ws_handshake->parse($chunk);
            if ($ws_handshake->is_done) {
                if(not $self->{mode} eq 'client') {
                    $handle->push_write($ws_handshake->to_string);
                }
                $self->{connected} = 1;
                if($self->{on_connect}) {
                    my $cb = $self->{on_connect};
                    &$cb($self);
                }
            }
        }
        
        $self->{connected} or return;

        # Post-Handshake
        $ws_frame->append($chunk);
        
        while (my $message = $ws_frame->next) {
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
    });

    if($self->{mode} eq 'client') {
        $self->{handle}->push_write($ws_handshake->to_string);
    }
}

sub _client_schedule_reconnect
{
    my ($self) = @_;

    $log->info("connection failed. reconnecting in 1 second");

    $self->{conn_w} = AnyEvent->timer (after => 1, cb => sub {
        $self->_start_client();
    });
}

sub _start_client
{
    my ($self) = @_;

    $self->{tcp_client} = AnyEvent::Socket::tcp_connect 'localhost', 7441, sub {
        my ($fh) = @_;
        if(! $fh) {
            $self->_client_schedule_reconnect();
            return;
        }

        $self->_setup_connection($fh);
    };
}

sub _start_server
{
    my ($self) = @_;
    $self->{tcp_server} = AnyEvent::Socket::tcp_server undef, 7441, sub {
        my ($fh, $host, $port) = @_;
        $self->_setup_connection($fh);
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
