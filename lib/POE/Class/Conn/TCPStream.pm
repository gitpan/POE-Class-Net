package POE::Class::Conn::TCPStream;

use POE::Class::Conn::Stream;
@ISA = qw(POE::Class::Conn::Stream);

use strict;

use POE;

use Socket qw/inet_ntoa/;
use Carp qw/croak/;

use POE::Class::Attribs
    remote_address => undef,
    remote_ip      => undef,
    remote_port    => undef,
    domain         => undef;

sub new {
    my $class = shift;

    my $self = $class->SUPER::new(@_);
    _init_internal_data($self);

    if (length($self->get_remote_address) == 4) {
        $self->set_remote_ip(inet_ntoa($self->get_remote_address));
    }
    elsif (defined $self->get_domain) {
        $self->set_remote_ip(
            Socket6::inet_ntop($self->get_domain, $self->get_remote_address)
        );
    }

    return $self;
}

sub DESTROY {
    $_[0]->SUPER::DESTROY;
    _destroy_internal_data($_[0]);
}

1;

__END__

=head1 NAME

POE::Class::Conn::TCPStream - Base class for tcp stream based connection
classes

=head1 SYNOPSIS

    # An echo server connection class
    package My::EchoServer;

    use POE qw(Class::Conn::TCPStream);

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

=head1 DESCRIPTION

POE::Class::Conn::TCPStream is a base class for tcp stream based connection.
This is probably the most common place to subclass in order to do things with
Client::* and Server::*. You would normally subclass this module, tell
Client::TCP or Server::TCP to use your subclassed connection class. In your
subclass you will need to override handler_conn_input as the default is to just
croak (it is a virtual method).

This module ISA L<POE::Class::Conn::Stream> which ISA L<POE::Class::Conn>. You
will want to see those modules for further details.

=head1 ACCESSORS

All accessors have three methods ala L<POE::Class::Attribs>. set_ATTRIB,
get_ATTRIB and ATTRIB. Set and get are obvious. ATTRIB is simply a set/get
method. See L<POE::Class::Attribs> for more details.

=over

=item remote_address

Packed remote address and port.

=item remote_ip

Remote IP address in dotted form.

=item remote_port

Remote port.

=item domain

The socket's domain. Will be one of AF_INET, AF_INET6, PF_INET or PF_INET6.

=back

=head1 METHODS

There are only two methods in this class. All other methods are inherited.

=over

=item new

This methods sets up internal data. It also sets the C<remote_ip()> based on
the C<remote_address()> and, if using ipv6, the C<domain()>.

=item DESTROY

This method simply cleans up internal data. If you override this method you
need to call it in your C<DESTROY()> method via C<SUPER::DESTROY> or your
program will leak.

=head1 TODO

Write better documentation.

=head1 AUTHOR

Scott Beck E<lt>sbeck@gossamer-threads.comE<gt>

=head1 SEE ALSO

L<POE>
L<POE::Class>
L<POE::Class::Conn>
L<POE::Class::Conn::Stream>

=cut


