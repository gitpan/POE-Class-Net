#!/usr/bin/perl

sub POE::Kernel::ASSERT_DEFAULT () { 1 }

use strict;
use POE;
use Test::More tests => 42;

BEGIN { use_ok('POE::Class::Server::TCP') }
require_ok('POE::Class::Server::TCP');

BEGIN { use_ok('POE::Class::Client::TCP') }
require_ok('POE::Class::Client::TCP');

package MyTest::Conn::Server::TCPStream;

use vars qw(@ISA);
use strict;
use Test::More;
use POE;

use POE::Class::Conn::TCPStream;

@ISA = qw(POE::Class::Conn::TCPStream);

sub handler_input {
    my ($self, $input) = @_[OBJECT, ARG0];
    return if $self->get_shutdown;

    is($input, 'PING', 'server got client input');
    $self->get_wheel->put("PONG");
    $self->yield('shutdown');
}

package MyTest::Conn::Client::TCPStream;

use vars qw(@ISA);
use strict;
use Test::More;
use POE;

use POE::Class::Conn::TCPStream;

@ISA = qw(POE::Class::Conn::TCPStream);

sub create_wheel {
    my $self = shift;
    $self->SUPER::create_wheel(@_);
    $self->get_wheel->put("PING");
}

sub handler_input {
    my ($self, $input) = @_[OBJECT, ARG0];
    return if $self->get_shutdown;

    is($input, 'PONG', 'server got client input');
    $self->yield('shutdown');
}

package MyTest::Server::TCP;

use vars qw(@ISA %Called $i);
use strict;
use Test::More;
use POE;

$i = 0;

@ISA = qw(POE::Class::Server::TCP);

sub connect {
    my $self = shift;
    $Called{connect} = $i++;
    $self->SUPER::connect;

    isa_ok($self->get_wheel, 'POE::Wheel::SocketFactory', 'Server: connect() created a POE::Wheel::SocketFactory');
}

sub disconnect {
    my $self = shift;
    $Called{disconnect} = $i++;
    $self->SUPER::disconnect;

    ok(!defined $self->get_wheel, 'Server: disconnect() set wheel to undef');
}

sub create_states {
    my $self = shift;
    $Called{create_states} = $i++;
    $self->SUPER::create_states;
    $poe_kernel->state(create_client => $self, 'handler_create_client');
}

sub handler_start {
    my $self = $_[OBJECT];
    $Called{handler_start} = $i++;
    $self->SUPER::handler_start(@_[1 .. $#_]);

    is($Called{create_states}, 1, 'Server: handler_start() called create_states');
    is($Called{connect}, 2, 'Server: handler_start called connect');

    $self->call('error', 'test', 1, 'Server: testing, ignore');
    is($Called{handler_error}, $i - 3, 'Server: handler_error() called');
    $self->SUPER::connect;
    $self->yield('create_client');
}

sub handler_create_client {
    my $self = $_[OBJECT];
    my $client = MyTest::Client::TCP->new(
        remote_port    => $self->get_port,
        remote_address => '127.0.0.1',
        conn_class     => 'MyTest::Conn::Client::TCPStream',
    );
    isa_ok($client, 'MyTest::Client::TCP', 'client new() returned an object of the correct type');

    my $client_session = $client->start;
    isa_ok($client_session, 'POE::Session', 'client start() returned the correct session');
}

sub handler_connection {
    my $self = $_[OBJECT];
    $Called{handler_connection} = $i++;
    $self->SUPER::handler_connection(@_[1 .. $#_]);
    my @children = $self->get_child_objects;
    isa_ok($children[1], 'MyTest::Conn::Server::TCPStream', 'Server: handler_connection() created child session');
}

sub handler_error {
    my $self = $_[OBJECT];
    $Called{handler_error} = $i++;
    $self->SUPER::handler_error(@_[1 .. $#_]);
    is($Called{handler_shutdown}, $i - 2, 'Server: handler_error() called handler_shutdown()');
}

sub handler_shutdown {
    my $self = $_[OBJECT];
    $Called{handler_shutdown} = $i++;
    $self->SUPER::handler_shutdown(@_[1 .. $#_]);
    is($Called{disconnect}, $i - 1, 'Server: handler_shutdown called disconnect');
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

package MyTest::Client::TCP;

use vars qw(@ISA %Called $i);
use strict;
use Test::More;
use POE;

$i = 0;

@ISA = qw(POE::Class::Client::TCP);

sub connect {
    my $self = shift;
    $Called{connect} = $i++;
    $self->SUPER::connect;

    isa_ok($self->get_wheel, 'POE::Wheel::SocketFactory', 'Client: connect() created a POE::Wheel::SocketFactory');
}

sub disconnect {
    my $self = shift;
    $Called{disconnect} = $i++;
    $self->SUPER::disconnect;

    ok(!defined $self->get_wheel, 'Client: disconnect() set wheel to undef');
    is($self->get_connected, 0, 'Client: disconnect() set connected status');
    is($Called{timeout_alarm}, $i - 1, 'Client: disconnect() called timeout_alarm');
}

sub create_states {
    my $self = shift;
    $Called{create_states} = $i++;
    $self->SUPER::create_states;
    $poe_kernel->state(connect => $self, 'handler_connect');
}

sub timeout_alarm {
    my $self = shift;
    $Called{timeout_alarm} = $i++;
    $self->SUPER::timeout_alarm(@_);
}

sub handler_start {
    my $self = $_[OBJECT];
    $Called{handler_start} = $i++;
    $self->SUPER::handler_start(@_[1 .. $#_]);

    is($Called{create_states}, 1, 'Client: handler_start() called create_states');
    is($Called{connect}, 2, 'Client: handler_start called connect');

    $self->call('error', 'test', 1, 'Client: testing, ignore');
    is($Called{handler_error}, $i - 4, 'Client: handler_error() called');
    $self->call('timeout');
    is($Called{handler_timeout}, $i - 3, 'Client: handler_error() called');

    $self->yield('connect');
}

sub handler_connect {
    # bypass connection tests
    $_[OBJECT]->SUPER::connect;
}

sub handler_connection {
    my $self = $_[OBJECT];

    $Called{handler_connection} = $i++;
    $self->SUPER::handler_connection(@_[1 .. $#_]);

    my @children = $self->get_child_objects;
    my $child = $children[0];
    isa_ok($child, 'MyTest::Conn::Client::TCPStream', 'Client: handler_connection() created child session');

    is($self->connected, 1, 'Client: handler_connection() set connected to 1');
    is($Called{timeout_alarm}, $i - 1, 'Client: handler_connection() called timeout_alarm');
}

sub handler_error {
    my $self = $_[OBJECT];
    $Called{handler_error} = $i++;
    $self->SUPER::handler_error(@_[1 .. $#_]);
    is($Called{handler_shutdown}, $i - 3, 'Client: handler_error() called handler_shutdown()');
}

sub handler_shutdown {
    my $self = $_[OBJECT];
    $Called{handler_shutdown} = $i++;
    $self->SUPER::handler_shutdown(@_[1 .. $#_]);
    is($Called{disconnect}, $i - 2, 'Client: handler_shutdown() called disconnect');
}

sub handler_timeout {
    my $self = $_[OBJECT];
    $Called{handler_timeout} = $i++;
    $self->SUPER::handler_timeout(@_[1 .. $#_]);
    is($Called{disconnect}, $i - 2, 'Client: handler_timeout() called disconnect');
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

package main;

use Socket;
use POE;

my $port = find_bindable_port();

my $server = MyTest::Server::TCP->new(
    port       => $port,
    address    => '127.0.0.1',
    conn_class => 'MyTest::Conn::Server::TCPStream',
);
isa_ok($server, 'MyTest::Server::TCP', 'server new() returned an object of the correct type');

my $server_session = $server->start;
isa_ok($server_session, 'POE::Session', 'server start() returned the correct session');
$poe_kernel->run;

sub find_bindable_port {
    local *SH;
    my $proto = getprotobyname('tcp');

    socket(SH, PF_INET, SOCK_STREAM, $proto) or return undef;
    setsockopt(SH, SOL_SOCKET, SO_REUSEADDR, pack("l", 1)) or return undef;
    my $host = inet_aton('127.0.0.1');
    # possible race condition
    for (reverse 3000 .. 31909) {
        if (bind(SH, sockaddr_in($_, $host))) {
            return $_;
        }
    }
    return undef;
}


