#!/usr/bin/perl

use lib '../lib';

# A simple echo client
package My::EchoClient::Conn;

use strict;
use POE qw(
    Wheel::ReadWrite
    Wheel::ReadLine
    Class::Conn::TCPStream
);

@My::EchoClient::Conn::ISA = qw(POE::Class::Conn::TCPStream);

my $Use_ReadLine = 1;

sub handler_start {
    my ($self, $kernel) = @_[OBJECT, KERNEL];
    $self->SUPER::handler_start(@_[1 .. $#_]);

    if ($Use_ReadLine) {
        $self->{rl} = POE::Wheel::ReadLine->new(InputEvent => 'input');
        $self->{rl}->get('> ');
        $SIG{__WARN__} = sub { $self->{rl}->put("@_") };
    }
    else {
        $self->{rl} = POE::Wheel::ReadWrite->new(
            InputEvent => 'input',
            Handle     => \*STDIN,
        );
    }
}

sub disconnect {
    my ($self) = @_;
    $self->SUPER::disconnect;
    delete $self->{rl};
}

sub create_states {
    my ($self) = @_;
    $self->SUPER::create_states;
    $poe_kernel->state(input => $self, 'handler_input');
}

sub handler_input {
    my ($self, $kernel, $input, $exception) = @_[OBJECT, KERNEL, ARG0, ARG1];
    return if $self->get_shutdown;
    if ($input eq 'close' or $input eq 'quit') {
        $self->yield('shutdown');
        return;
    }
    if ($Use_ReadLine) {
        if (defined $input) {
            $self->{rl}->addhistory($input);
            $kernel->yield(put => $input);
            $self->{rl}->get('> ');
        }
        else {
            $self->{rl}->put($exception);
        }
    }
    else {
        $kernel->yield(put => $input);
    }
}

sub handler_input {
    my ($self, $input) = @_[OBJECT, ARG0];
    return if $self->get_shutdown;
    if ($Use_ReadLine) {
        $self->{rl}->put("< $input");
        $self->{rl}->get('> ');
    }
    else {
        print "< $input\n";
    }
}

package main;

use strict;
use POE qw(Class::Client::TCP);

my $host = shift;
die "Usage: $0 hostname\n" unless defined $host;

my $client = POE::Class::Client::TCP->new(
    remote_port    => 'echo',
    remote_address => $host,
    conn_class     => 'My::EchoClient::Conn',
);

$client->start;

$poe_kernel->run;

