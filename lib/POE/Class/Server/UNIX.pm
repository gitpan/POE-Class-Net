package POE::Class::Server::UNIX;

@ISA = qw(POE::Class);

use strict;

use Socket qw/AF_UNIX/;
use POE qw/Wheel::SocketFactory Class/;

use Carp;

use POE::Class::Attribs
    path       => undef,
    wheel      => undef,
    conn_class => 'POE::Class::Conn::UNIXStream';

# methods

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    _init_internal_data($self);
    return $self;
}

sub DESTROY {
    $_[0]->SUPER::DESTROY;
    _destroy_internal_data($_[0]);
}

sub connect {
    my $self = shift;
    croak "Unknown arguments passed to connect()" if @_;

    # XXX have something for permissions/umask
    $self->set_wheel(
        POE::Wheel::SocketFactory->new(
            SocketDomain => AF_UNIX,
            BindAddress  => $self->get_path,
            Reuse        => 'yes',
            SuccessEvent => 'connection',
            FailureEvent => 'error'
        )
    );
}

sub disconnect {
    my $self = shift;
    croak "Unknown arguments to disconnect()" if @_;

    $self->set_wheel(undef);
}

sub create_states {
    my $self = shift;
    croak "Unknown arguments passed to create_states()" if @_;

    $self->SUPER::create_states;

    for (qw/error connection/) {
        $poe_kernel->state($_ => $self, "handler_$_");
    }
}

# handlers

sub handler_start {
    my $self = $_[OBJECT];
    croak "No path defined before session started"
        unless defined $self->get_path;
    $self->SUPER::handler_start(@_[1 .. $#_]);

    $self->connect;
}

sub handler_connection {
    my ($self, $kernel, $heap, $socket, $remote_address) =
        @_[OBJECT, KERNEL, HEAP, ARG0 .. $#_];

    $self->get_conn_class->new(
        socket => $socket,
        path   => $remote_address
    )->start;
}

sub handler_shutdown {
    my $self = $_[OBJECT];
    $self->SUPER::handler_shutdown(@_[1 .. $#_]);

    $self->disconnect;
}

sub handler_error {
    my ($self, $syscall, $errno, $error) = @_[OBJECT, ARG0 .. ARG2];
    warn "Got $syscall error $errno ($error)\n";
    $self->call('shutdown');
}

1;

__END__

=head1 NAME

POE::Class::Server::UNIX - Base class to create a POE UNIX Server

=head1 SYNOPSIS


    #!/usr/bin/perl

    use strict;


    # A simple echo server on a UNIX socket!
    package My::EchoServer;

    use POE;

    use base 'POE::Class::Conn::UNIXStream';

    sub handler_conn_input {
        my ($self, $input) = @_[OBJECT, ARG0];
        return if $self->get_shutdown;
        $self->get_wheel->put($input);
    }

    package main;

    use POE qw/Class::Server::UNIX/;

    my $server = new POE::Class::Server::UNIX(
        port       => 'echo',
        conn_class => 'My::EchoServer',
        alias      => 'echo'
    );
    # - or -
    $server = new POE::Class::Server::UNIX;
    $server->set_path('/tmp/foo.sock');
    $server->set_conn_class('My::EchoServer');
    $server->set_alias('echo');
    # - or -
    my $server = new POE::Class::Server::UNIX;
    $server->configure(
        path       => '/tmp/foo.sock',
        conn_class => 'My::EchoServer',
        alias      => 'echo'
    );

    # Creates the session
    my $session = $server->start;
    printf "Created echo session %d\n", $session->ID;

    $poe_kernel->run;

=head1 DESCRIPTION

POE::Class::Server::UNIX is a base class for creating POE UNIX Servers. Through
inheritance with other POE::Class:: classes it provides a faily simple subclass
interface. This document will touch on all methods and handlers within this
module and realized though inheritance except for methods in L<POE::Class>.

=head1 METHODS

=over

=item new

The constructor. If takes a hash of arguments which correspond to accessor
functions of the same name.

=item start

Creates the and returns a new session specified by C<set_session_type()>,
defaults to L<POE::Session>.  You should setup the connection information before
calling this method as the SocketFactory will be created when this is called.
Inherited.

=item disconnect

Disconnects the server. This does not kill and current connections
L<POE::Class::Conn> for that.

=item connect

This method creates a POE::Wheel::SocketFactory with current object information
from C<get_port()>, C<get_address()> and C<get_domain()>. The accessor
C<set_wheel()> is called with the new SocketFactory.

=item create_states

Creates the following object states in the current session:
    State             Handler
    error           - handler_error
    connection      - handler_connection

=item other methods

L<POE::Class> for a complete list.

=back

=head1 ACCESSOR METHODS

=over

=item get_alias

=item set_alias

Accessor method for the session alias. If no alias is set when C<start()> is
called no alias will be created. Inherited.

=item get_shutdown

=item set_shutdown

Accessor method for shutdown. When we are shutdown no more connections will be
accepted. This does not mean the session will exit right away. When all connection
classes have finished the session will end. Inherited.

=item get_session_type

=item set_session_type

Specifies the class used to created the session when C<start()> is called.
Defaults to L<POE::Session>.

=item get_path

=item set_path

Path to the socket file to use.

=item get_conn_class

=item set_conn_class

Sets the connection class used when a new connection is accepted. Defaults to
L<POE::Class::Conn::UNIXStream>. You will want to set this to a subclass of
L<POE::Class::Conn::UNIXStream>.

=item get_wheel

=item set_wheel

Sets the current wheel, usually a L<POE::Wheel::SocketFactory>. This method is
called from C<connect()> with a L<POE::Wheel::SocketFactory>.

=back

=head1 HANDLERS

=over

=item handler_start

This handler sets a session alias if one was defined and then calles
C<connect()>.

=item handler_child

Cleans up connections stored via C<set_connections()> and C<session_id_to_conn()>.

=item handler_shutdown

Sets shutdown to true and calles C<disconnect()>.

=item handler_error

Warns with the error and calles C<disconnect()>.

=item handler_connection

Called from L<POE::Wheel::SocketFactory> when a connection is accepted. Creates
a new connection object defined by C<set_conn_class()>.

=back

=head1 TODO

Write better documentation.

=head1 AUTHOR

Scott Beck E<lt>sbeck@gossamer-threads.comE<gt>

=head1 SEE ALSO

L<POE>
L<POE::Class>
L<POE::Class::Conn>
L<POE::Class::Conn::Stream>
L<POE::Class::Conn::UNIXStream>

=cut

