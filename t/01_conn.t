#!/usr/bin/perl

use strict;
use POE;
use Test::More tests => 32;

BEGIN { use_ok('POE::Class::Conn') }
require_ok('POE::Class::Conn');

my $i = 0;
my %Called;
my $Put = '';

package MyWheel;

sub new {
    return bless [], shift;
}

sub put {
    $Called{put} = $i++;
    $Put = $_[1];
    return 0;
}

sub get_driver_out_octets {
    $Called{get_driver_out_octets} = $i++;
    return 0;
}

package MyTest::Conn;

use strict;
import Test::More;
use POE;
use POSIX qw(ECONNABORTED);


@MyTest::Conn::ISA = qw(POE::Class::Conn);

sub create_states {
    my $self = shift;
    $Called{create_states} = $i++;
    for (qw(test1 test2 test3)) {
        $poe_kernel->state($_ => $self, "handler_$_");
    }
    $self->SUPER::create_states;
}

sub create_wheel {
    my $self = shift;
    $self->set_wheel(new MyWheel);
    $Called{create_wheel} = $i++;
}

sub disconnect {
    my $self = shift;
    $Called{disconnect} = $i++;
    $self->SUPER::disconnect;
}

sub handler_start {
    my $self = $_[OBJECT];
    $Called{handler_start} = $i++;
    $self->SUPER::handler_start(@_[1 .. $#_]);
    is($Called{create_states}, 1, 'handler_start() called create_states');
    is($Called{create_wheel}, 2, 'handler_start() called create_wheel');

    $self->call('error', 'test', ECONNABORTED, 'testing, ignore');
    is($Called{handler_error}, 3, 'handler_error() yielded ok');
    ok($self->get_got_error, 'handler_error() set got_error');
    $self->set_wheel(new MyWheel);

    $self->yield('test1');
}

sub handler_test1 {
    my $self = $_[OBJECT];

    is($Called{handler_shutdown}, 4, 'handler_error() yielded shutdown');
    is($Called{disconnect}, 5, 'handler_shutdown() called disconnect');

    $self->set_shutdown_on_error(0);
    $self->call('error', 'test', ECONNABORTED, 'testing, ignore');
    is($Called{handler_error}, 6, 'handler_error() yielded ok');
    $self->set_wheel(new MyWheel);

    ok(!$self->get_got_error, 'handler_error() did not set got_error');
    $self->yield('test2');
}

sub handler_test2 {
    my $self = $_[OBJECT];

    is($Called{handler_shutdown}, 4, 'handler_error() did not yield shutdown');

    $self->yield(put => "test3\n");
    $self->yield('test3');
}

sub handler_test3 {
    my $self = $_[OBJECT];

    is($Called{put}, 7, 'handler_put() called put()');
    is($Put, "test3\n", 'wheel got correct output');
    $self->set_shutdown(1);
    $self->call('flush');
    is($Called{disconnect}, 8, 'handler_flush() called disconnect in shutdown mode');
    $self->set_shutdown(0);
    $self->call('flush');
    is($Called{disconnect}, 8, 'handler_flush() did not call disconnect not in shutdown mode');
}

sub handler_error {
    my $self = $_[OBJECT];
    $Called{handler_error} = $i++;
    $self->SUPER::handler_error(@_[1 .. $#_]);
}

sub handler_shutdown {
    my $self = $_[OBJECT];
    $Called{handler_shutdown} = $i++;
    $self->SUPER::handler_shutdown(@_[1 .. $#_]);
}

package main;

use strict;
import Test::More;
import POE;

my $conn = POE::Class::Conn->new;
isa_ok($conn, 'POE::Class::Conn');
isa_ok($conn, 'POE::Class');

can_ok($conn, qw(
    socket
    set_socket
    get_socket
    wheel
    set_wheel
    get_wheel
    shutdown_on_error
    set_shutdown_on_error
    get_shutdown_on_error
    driver
    get_driver
    set_driver
    filter
    set_filter
    get_filter
    got_error
    set_got_error
    get_got_error

    new
    DESTROY
    create_states
    create_wheel
    disconnect

    handler_start
    handler_input
    handler_put
    handler_error
    handler_flush
    handler_shutdown
));

my $driver = $conn->get_driver;
ok(defined $driver, 'get_driver() returned a defined value');
ok(UNIVERSAL::isa($driver, 'POE::Driver::SysRW'), 'Driver defaults to POE::Driver::SysRW');

my $filter = $conn->get_filter;
ok(defined $filter, 'get_filter() returned a defined value');
ok(UNIVERSAL::isa($filter, 'POE::Filter::Line'), 'Filter defaults to POE::Filter::Line');

my $shutdown_on_error = $conn->get_shutdown_on_error;
ok(defined $shutdown_on_error, 'shutdown_on_error() returned a defined value');
is($shutdown_on_error, 1, 'shutdown_on_error() defaults to 1');

my $socket = $conn->get_socket;
ok(!defined $socket, 'Socket defaulted to undefined');

my $wheel = $conn->get_wheel;
ok(!defined $wheel, 'Wheel defaults to undefined');


ok(!eval { $conn->create_wheel; 1 }, 'Virtual method create_wheel() dies');
ok(!eval { $conn->handler_input; 1 }, 'Virtual method handler_input() dies');

$conn->set_socket(1);
$conn->set_wheel(1);
$conn->disconnect;
ok(!defined $conn->get_socket, 'disconnect() undefines socket');
ok(!defined $conn->get_wheel, 'disconnect() undefines wheel');

$conn = MyTest::Conn->new;

my $session = $conn->start;
isa_ok($session, 'POE::Session', 'start returned a valid session');

$poe_kernel->run;

is($Called{handler_start}, 0, 'handler_start() called');

