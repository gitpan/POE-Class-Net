#!/usr/bin/perl

use strict;
use POE;
use Test::More tests => 11;

BEGIN {
    SKIP: {
        skip("no unix sockets on win32", 11)
            if $^O eq 'MSWin32';
    }
    if ($^O eq 'MSWin32') {
        exit;
    }
}

my $Socket_File = '/tmp/conn_unixstream_test.sock';


BEGIN { use_ok('POE::Class::Conn::UNIXStream') }
require_ok('POE::Class::Conn::UNIXStream');

package MyTest::Conn::UNIXStream;

use vars qw(@ISA);
use strict;
import Test::More;
use POE;

@ISA = qw(POE::Class::Conn::UNIXStream);

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
    unlink $Socket_File if -e $Socket_File;
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

    unlink $Socket_File if -e $Socket_File;
    $self->set_server_wheel(
        POE::Wheel::SocketFactory->new(
            SocketDomain => AF_UNIX,
            BindAddress  => $Socket_File,
            SuccessEvent => 'server_accept',
            FailureEvent => 'error'
        )
    );
    $self->set_client_wheel(
        POE::Wheel::SocketFactory->new(
            SocketDomain  => AF_UNIX,
            RemoteAddress => $Socket_File,
            SuccessEvent  => 'client_connect',
            FailureEvent  => 'error'
        )
    );
}

sub handler_server_accept {
    my ($self, $socket, $raddress, $rport)  = @_[OBJECT, ARG0 .. $#_];
    my $conn = MyTest::Conn::UNIXStream->new(
        name   => 'server',
        socket => $socket,
        path   => $Socket_File,
    );
    isa_ok($conn, 'POE::Class::Conn::UNIXStream');
    is($conn->get_path, $Socket_File, 'path set');

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
    my ($self, $socket, $raddress, $rport)  = @_[OBJECT, ARG0 .. $#_];

    my $conn = MyTest::Conn::UNIXStream->new(
        name   => 'client',
        socket => $socket,
        path   => $Socket_File,
    );
    isa_ok($conn, 'POE::Class::Conn::UNIXStream');
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

MyTest::ClientServer->new->start;

$poe_kernel->run;

