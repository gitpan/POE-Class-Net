package POE::Class::Conn;

use POE::Class;
@ISA = qw(POE::Class);

use strict;

use POE qw/
    Driver::SysRW
    Filter::Line
/;
use POE::Class::Attribs
    socket            => undef,
    wheel             => undef,
    got_error         => undef,
    shutdown_on_error => 1,
    driver            => sub { POE::Driver::SysRW->new },
    filter            => sub { POE::Filter::Line->new };

use POSIX qw/ECONNABORTED ECONNRESET/;
use Carp;

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

sub create_states {
    my $self = shift;
    croak "Unknown arguments passed to create_states()" if @_;

    for (qw/input error flush shutdown put/) {
        $poe_kernel->state($_ => $self, "handler_$_");
    }
}

sub create_wheel {
    my $self = $_[OBJECT];
    croak "virtual method create_wheel() not defined by ",
        ref($self);
}

sub disconnect {
    my $self = shift;
    croak "Unknown arguments to disconnect()" if @_;
    $self->set_wheel(undef);
    $self->set_socket(undef);
}

# handlers

sub handler_start {
    my $self = $_[OBJECT];
    $self->SUPER::handler_start(@_[1 .. $#_]);

    $self->create_wheel;
}

sub handler_input {
    my $self = $_[OBJECT];
    croak "virtual method hanlder_input() not defined by ",
        ref($self);
}

sub handler_put {
    my ($self, $output) = @_[OBJECT, ARG0];
    $self->get_wheel->put($output);
}

sub handler_error {
    my ($self, $kernel, $operation, $errno, $errstr) =
        @_[OBJECT, KERNEL, ARG0 .. ARG2];
    unless ($operation eq "read" and ($errno == 0 or $errno == ECONNRESET)) {
        $errstr = "(no error)" unless $errno;
        warn("Connection got $operation error $errno ($errstr)\n");
    }
    unless ($operation eq 'accept' and $errno == ECONNABORTED) {
        if ($self->get_shutdown_on_error) {
            $self->set_got_error(1);
            $self->yield("shutdown");
        }
    }
}

sub handler_flush {
    my $self = $_[OBJECT];
    if ($self->get_shutdown) {
        $self->disconnect;
    }
}

sub handler_shutdown {
    my $self = $_[OBJECT];
    $self->set_shutdown(1);
    my $wheel = $self->get_wheel;
    if (defined $wheel) {
        if (
            $self->get_got_error or
            not $wheel->get_driver_out_octets
        )
        {
            $self->set_got_error(0);
            $self->disconnect;
        }
    }
}

# access methods

1;

__END__

=head1 NAME

POE::Class::Conn - Base class for all connection classes

=head1 SYNOPSIS

    package My::Conn;

    use strict;
    use base 'POE::Class::Conn';

    use POE qw/
        Class::Server::TCP
        Wheel::ReadWrite
    /;

    sub new {
        my $class = shift;

        my $self = $class->SUPER::new(@_);

        # Do something

        return $self;
    }

    sub create_wheel {
        my ($self) = @_;
        $self->wheel(
            POE::Wheel::ReadWrite->new(
                Handle       => $self->get_socket,
                Driver       => $self->get_driver,
                Filter       => $self->get_filter,
                InputEvent   => 'input',
                ErrorEvent   => 'error',
                FlushedEvent => 'flush'
            )
        );
    }

    sub handler_input {
        my ($self, $input) = @_[OBJECT, ARG0];
        print "Got input: $input\n";
    }

    package main;

    use POE qw/Class::Server::TCP/;

    my $server = POE::Class::Server::TCP->new(
        address          => 'localhost',
        connection_class => 'My::Conn'
    );
    # - or -
    my $server = POE::Class::Server::TCP;
    $server->configure(
        address          => 'localhost',
        connection_class => 'My::Conn'
    );
    # - or -
    my $server = POE::Class::Server::TCP->new;
    $server->set_address('localhost');
    $sevrer->set_connection_class('My::Conn');

    printf "Created server: %d\n", $server->ID;

    # Create the session
    my $session = $server->start;
    printf "Server session: %d\n", $session->ID;

    $poe_kernel->run;

=head1 DESCRIPTION

Base class for all POE::Class::Conn classes. Conn classes represent an IO bound connection
either server or client.

=head1 METHODS

=over

=item new

The constructor. It takes a hash of arguments which correspond to accessor
functions of the same name.

=item create_states

This method is called from C<handler_start()>. It creates the states needed for
IO on the given socket.  The states created are:

=over

=item input - handle socket input

=item error - handler socket errors

=item flush - flush events from the socket

=item shutdown - shutdown this portion of the session

=item put - send output to the socket

=back

The handlers for these states are explained below.

=item create_wheel

This is a virtual method. It is called from C<handler_start()> and is expected
to create a wheel object and store it with method C<set_wheel()>.
C<$self-E<gt>get_socket> contains the socket you should use.
C<$self-E<gt>get_filter> contains the filter you should use.
C<$self-E<gt>get_driver> contains the driver to use.

=item disconnect

This method removes the wheel and socket from the object.

=back

=head1 ACCESSOR METHODS

All accessors have three methods ala L<POE::Class::Attribs>. set_ATTRIB,
get_ATTRIB and ATTRIB. Set and get are obvious. ATTRIB is simply a set/get
method. See L<POE::Class::Attribs> for more details.

=over

=item socket

Stores for the socket.

=item wheel

Stores for the wheel.

=item shutdown_on_error

Stores a boolean wether we should shutdown on socket errors.

=item shutdown

Stores a boolean wether we are being shutdow.

=item driver

Stores the diver to use for IO. If no driver is defined this creates a new
L<POE::Driver::SysRW>, stores it, and returns it.

=item filter

Stores the filter to use for IO. If no filter is defined this creates a new
L<POE::Filter::Line>, stores it, and returns it.

=item got_error

Set to true if Conn get an error and the C<shutdown_on_error()> flag is set.
This is checked in C<handler_shutdown()> and set in C<handler_error()>.

=back

=head1 HANDLERS

=over 1

=item handler_input

This is a virtual state, the subclass must defined it. It is called with the
input as ARG0.

=item handler_put

This state simply takes ARG0 and sends it to C<$self-E<gt>get_wheel-E<gt>put()>.

=item handler_error

Called when there is a socket error. Warns the error and shuts down if
appropriate.

=item handler_flush

When the socket is flush this state happens. If we are in a shutdown state
calles C<$self-E<gt>disconnect>.

=item handler_shutdown

This handler puts us in a shutdown state and calles C<$self-E<gt>disconnect>
if there is no more input pending.

=back

=head1 TODO

Write better documentation.

=head1 AUTHOR

Scott Beck E<lt>sbeck@gossamer-threads.comE<gt>

=head1 SEE ALSO

L<POE>
L<POE::Class>

=cut

