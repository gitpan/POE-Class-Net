#!/usr/bin/perl

use strict;
use POE;
use Test::More tests => 10;

BEGIN { use_ok('POE::Class::Conn::Stream') }
require_ok('POE::Class::Conn::Stream');

package MyTest::Conn::Stream;

use vars qw(@ISA);
use strict;
import Test::More;
use POE;

@ISA = qw(POE::Class::Conn::Stream);

use POE::Class::Attribs name => undef;

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    _init_internal_data($self);
    return $self;
}

sub DESTROY {
    my $self = shift;
    $self->SUPER::DESTROY;
    _destroy_internal_data($self);
}

sub create_wheel {
    my $self = shift;

    $self->SUPER::create_wheel;
    my $name = $self->get_name;
    isa_ok($self->get_wheel, 'POE::Wheel::ReadWrite', "$name created wheel");
    if ($name eq 'client') {
        $self->get_wheel->put("PING");
    }
}

sub handler_input {
    my ($self, $input) = @_[OBJECT, ARG0];
    return if $self->get_shutdown;

    my $name = $self->get_name;
    if ($name eq 'server') {
        is($input, 'PING', 'server got client input');
        $self->get_wheel->put("PONG");
    }
    else {
        is($input, 'PONG', 'client got server input');
    }
    $self->yield('shutdown');
}

package MyTest::ClientServer;

use vars qw(@ISA);
use strict;
import Test::More;
use Socket;
use POE qw(
    Wheel::SocketFactory
);

use POE::Class::Attribs
    client_wheel => undef,
    server_wheel => undef;

@ISA = qw(POE::Class);

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    _init_internal_data($self);
    return $self;
}

sub DESTROY {
    my $self = shift;
    $self->SUPER::DESTROY;
    _destroy_internal_data($self);
}

sub create_states {
    my $self = shift;
    for (qw/server_accept client_connect error/) {
        $poe_kernel->state($_, $self, "handler_$_");
    }
}

sub handler_start {
    my $self = $_[OBJECT];
    $self->SUPER::handler_start(@_[1 .. $#_]);

    SKIP: {
        my $port = find_bindable_port();
        print "Port: $port\n";
        skip("Could not find a port to bind to", 8) unless defined $port;
        $self->set_server_wheel(
            POE::Wheel::SocketFactory->new(
                BindAddress  => '127.0.0.1',
                BindPort     => $port,
                SuccessEvent => 'server_accept',
                FailureEvent => 'error'
            )
        );
        $self->set_client_wheel(
            POE::Wheel::SocketFactory->new(
                RemoteAddress => '127.0.0.1',
                RemotePort    => $port,
                SuccessEvent  => 'client_connect',
                FailureEvent  => 'error'
            )
        );
    }
}

sub handler_server_accept {
    my ($self, $socket)  = @_[OBJECT, ARG0];
    my $conn = MyTest::Conn::Stream->new(
        name           => 'server',
        socket         => $socket,
    );
    isa_ok($conn, 'POE::Class::Conn::Stream');
    my $session = $conn->start;
    isa_ok($session, 'POE::Session');
}

sub handler_child {
    my ($self, $what) = @_[OBJECT, ARG0];
    $self->SUPER::handler_child(@_[1 .. $#_]);
    if ($what eq 'lose') {
        my @children = $self->get_child_objects;
        if (@children == 0) {
            $self->yield('shutdown');
        }
    }
}

sub handler_shutdown {
    my $self = $_[OBJECT];
    $self->set_client_wheel(undef);
    $self->set_server_wheel(undef);
}

sub handler_client_connect {
    my ($self, $socket) = @_[OBJECT, ARG0];

    my $conn = MyTest::Conn::Stream->new(
        name           => 'client',
        socket         => $socket,
    );
    isa_ok($conn, 'POE::Class::Conn::Stream');
    my $session = $conn->start;
    isa_ok($session, 'POE::Session');
}

sub handler_error {
    my ($self, $syscall, $errno, $error) = @_[OBJECT, ARG0 .. ARG2];
    warn "Got $syscall error $errno ($error)\n";
    if ($errno != 0) {
        $self->set_server_wheel(undef);
        $self->set_client_wheel(undef);
    }
}

sub find_bindable_port {
    local *SH;
    my $proto = getprotobyname('tcp');

    socket(SH, PF_INET, SOCK_STREAM, $proto) or return undef;
    setsockopt(SH, SOL_SOCKET, SO_REUSEADDR, pack("l", 1)) or return undef;
    my $host = inet_aton('127.0.0.1');
    # possible race condition
    for (reverse 3000 .. 31909) {
        if (bind(SH, sockaddr_in($_, $host))) {
            close SH;
            return $_;
        }
    }
    return undef;
}

MyTest::ClientServer->new->start;

$poe_kernel->run;

