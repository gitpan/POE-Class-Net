package POE::Class::Client::TCP;

@ISA = qw(POE::Class);
use strict;

use POE qw/Wheel::SocketFactory Class/;

use Carp;

use POE::Class::Attribs
    alarm_id       => undef,
    timeout        => undef,
    connected      => undef,
    remote_port    => undef,
    remote_address => undef,
    port           => undef,
    domain         => undef,
    address        => undef,
    wheel          => undef,
    conn_class     => 'POE::Class::Conn::TCPStream';

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

    $self->set_wheel(
        POE::Wheel::SocketFactory->new(
            RemoteAddress => $self->get_remote_address,
            RemotePort    => $self->get_remote_port,
            SocketDomain  => $self->get_domain,
            BindAddress   => $self->get_address,
            BindPort      => $self->get_port,
            SuccessEvent  => 'connection',
            FailureEvent  => 'error'
        )
    );
    $self->timeout_alarm(1);
}

sub disconnect {
    my $self = shift;
    croak "Unknown arguments to diconnect()" if @_;

    $self->timeout_alarm(0);
    $self->set_connected(0);
    $self->set_wheel(undef);
}

sub create_states {
    my $self = shift;
    croak "Unknown arguments passed to create_states()" if @_;

    $self->SUPER::create_states;

    for (qw/error connection timeout/) {
        $poe_kernel->state($_ => $self, "handler_$_");
    }
    $poe_kernel->state(_child => $self, "handler_child");
}

sub timeout_alarm {
    my $self = shift;
    my $status = shift;

    if (defined $self->get_alarm_id) {
        $poe_kernel->alarm_remove($self->get_alarm_id);
        $self->set_alarm_id(undef);
    }

    if ($status and $self->get_timeout) {
        $self->set_alarm_id(
            $self->delay_set(
                timeout => $self->get_timeout
            )
        );
    }
}

# handlers

sub handler_start {
    my $self = $_[OBJECT];
    croak "No remote port setup for connection"
        unless defined $self->get_remote_port;

    croak "No remote address setup for connection"
        unless defined $self->get_remote_address;

    $self->SUPER::handler_start(@_[1 .. $#_]);

    $self->connect;
}

sub handler_connection {
    my ($self, $kernel, $heap, $socket,
            $remote_address, $remote_port) =
        @_[OBJECT, KERNEL, HEAP, ARG0 .. $#_];

    $self->timeout_alarm(0);

    $self->get_conn_class->new(
        socket         => $socket,
        remote_address => $remote_address,
        remote_port    => $remote_port,
        domain         => $self->get_domain,
    )->start;
    $self->set_connected(1);
}

sub handler_error {
    my ($self, $syscall, $errno, $error) = @_[OBJECT, ARG0 .. ARG2];
    warn "Got $syscall error $errno ($error)\n";
    $self->call('shutdown');
}

sub handler_timeout {
    my $self = $_[OBJECT];
    $self->disconnect;
}

sub handler_shutdown {
    my ($self, $kernel) = @_[OBJECT, KERNEL];
    $self->SUPER::handler_shutdown(@_[1 .. $#_]);

    $self->post_children('shutdown');
    $self->disconnect;
}

1;

__END__

=head1 NAME

POE::Class::Client::TCP - Base class to create POE based TCP clients

=head1 SYNOPSIS

    #!/usr/bin/perl

    use strict;

    # A simple echo client
    package My::EchoClient::Conn;

    use POE qw(
        Wheel::ReadWrite
        Wheel::ReadLine
        Class::Conn::TCPStream
    );

    @My::EchoClient::Conn::ISA = qw(POE::Class::Conn::TCPStream);

    sub handler_start {
        my ($self, $kernel) = @_[OBJECT, KERNEL];
        $self->SUPER::handler_start(@_[1 .. $#_]);

        $self->{rl} = POE::Wheel::ReadLine->new(InputEvent => 'input');
        $self->{rl}->get('> ');
        $SIG{__WARN__} = sub { $self->{rl}->put("@_") };
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
        if (defined $input) {
            $self->{rl}->addhistory($input);
            $kernel->yield(put => $input);
            $self->{rl}->get('> ');
        }
        else {
            $self->{rl}->put($exception);
        }
    }

    sub handler_input {
        my ($self, $input) = @_[OBJECT, ARG0];
        return if $self->get_shutdown;
        $self->{rl}->put("< $input");
        $self->{rl}->get('> ');
    }

    package main;

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

=head1 DESCRIPTION

POE::Class::Client::TCP is a base class for creating POE based TCP clients.
This class uses POE::Class as a base for Object/Session glue. Each connection
spawns a new sonnection session. See L<POE::Class::Conn> for details on the
connection class.

=head1 HANDLERS

=over

=item _start => handler_start

Error checking on remote_port and remote_address. Calles the method
C<connect()> which performs the actual connection.

=item connection => handler_connection

Fired from L<POE::Wheel::SocketFactory> when a connection is established.
Creates a new connection object of C<get_conn_class()> type and calles the
method C<start()> on it. Sets C<connected()> to one.

=item error => handler_error

This event happens when L<POE::Wheel::SocketFactory> encounters an error. It
C<warn()>s the error and C<call()>s shutdown.

=item timeout => handler_timeout

Client::TCP set's an alarm in C<connect()> to call this handler. When the
connection happens the alarm is reset. This event signifies the connection has
timed out. The method C<disconnect()> is called here.

=item shutdown => handler_shutdown

You shuold yield this event when you want the connection shutdown. It posts the
shutdown event to it's children and then calles the method C<disconnect()>.

=back

=head1 ACCESSORS

All accessors have three methods ala L<POE::Class::Attribs>. set_ATTRIB,
get_ATTRIB and ATTRIB. Set and get are obvious. ATTRIB is simply a set/get
method. See L<POE::Class::Attribs> for more details.

=over

=item alarm_id

Used interally to store the current alarm ID for timeout.

=item timeout

Sets the timeout in seconds before a connection is established.

=item connected

Whether Client::TCP has established a connection or not.

=item remote_port

The port Client::TCP is connecting to.

=item remote_address

The address Client::TCP is connecting to.

=item port

Local port to bind to for the connection.

=item address

The local address to bind to.

=item domain

The socket domain to use when connecting.

=item wheel

Stores the L<POE::Wheel::SocketFactory> object.

=item conn_class

Sets the connection class to use when a connection comes in. The C<new()> contructor
method is called on this class with the following arguments:

        socket         => socket that just connected
        remote_address => remote address of the socket
        remote_port    => remote port of the socket
        domain         => the domain as set by C<domain()> (for ipv6)

The C<start()> method is then called on the returned object. This class defaults
to L<POE::Class::Conn::TCPStream>, which is NOT what you want. You should set it
to your subclass of that class or L<POE::Class::Conn::TCPStream> will just croak
with an error about virtual methods not defined in the subclass.

=back

=head1 METHODS

=over

=item new

Constructor, sets up internal data.

=item DESTROY

Destructor, frees internal data.

=item connect

Creates a new L<POE::Wheel::SocketFactory> object with parameters specified by accessors
and begines an alarm for this connect by calling the method C<timeout_alarm(1)>.

=item disconnect

Removes the connection alarm by calling C<timeout_alarm(0)>. Sets the flag
C<connected()> to zero. Sets the L<POE::Wheel::SocketFactory> object to undef
C<set_wheel(undef)>.

=item create_states

Creates the states talked about in L</"HANDLERS"> section that are not set by
the base class L<POE::Class>.

=item timeout_alarm

Called to add or remove the connection alarm. First argument it s boolean. If
true the alarm is removed and re-added with C<timeout()> else the alarm is just
removed.

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
L<POE::Class::Conn::TCPStream>

=cut


