#!/usr/bin/perl

use lib '../lib';
use strict;

sub POE::Kernel::ASSERT_DEFAULT () { 1 }
#sub POE::Kernel::TRACE_REFCNT () { 1 }

# A simple echo server
package My::EchoServer;

use POE qw(
    Class::Server::TCP
    Class::Conn::TCPStream
);

@My::EchoServer::ISA =  qw(POE::Class::Conn::TCPStream);

sub handler_conn_input {
    my ($self, $input) = @_[OBJECT, ARG0];
    return if $self->get_shutdown;
    print "<< $input\n";
    $self->get_wheel->put($input);
}

sub handler_start {
    $_[OBJECT]->SUPER::handler_start(@_[1 .. $#_]);
    printf "Conn session %d started\n", $_[SESSION]->ID;
}

sub handler_stop {
    $_[OBJECT]->SUPER::handler_stop(@_[1 .. $#_]);
    printf "Conn session %d stopped\n", $_[SESSION]->ID;
}

package main;

use POE qw/Class::Server::TCP/;

my $server = new POE::Class::Server::TCP(
    port       => 'echo',
    conn_class => 'My::EchoServer',
);

printf "Created server with ID %d\n", $server->ID;

my $session = $server->start;
printf "Created session with ID %d\n", $session->ID;

$poe_kernel->run;

