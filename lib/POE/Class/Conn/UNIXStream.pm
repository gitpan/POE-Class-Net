package POE::Class::Conn::UNIXStream;
use POE::Preprocessor(isa => "POE::Class");

use POE::Class::Conn::Stream;
@ISA = qw(POE::Class::Conn::Stream);

use strict;

use POE;

use Carp qw/croak/;

use POE::Class::Attribs path => undef;

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    _init_internal_data($self);
    return $self;
}

sub DESTROY {
    my ($self) = @_;
    $self->SUPER::DESTROY;
    _destroy_internal_data($_[0]);
}

1;

__END__

=head1 NAME

POE::Class::Conn::UNIXStream - Base class for unix stream based connection
classes

=head1 SYNOPSIS

    # An echo server connection class
    # Note that it looks almost identical to a TCP connection
    # class
    package My::EchoServer;

    use POE qw(Class::Conn::UNIXStream);

    @My::EchoServer::ISA =  qw(POE::Class::Conn::UNIXStream);

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

POE::Class::Conn::UNIXStream is a base class for unix stream based connection.
This is probably the most common place to subclass in order to do things with
Client::* and Server::*. You would normally subclass this module, tell
Client::UNIX or Server::UNIX to use your subclassed connection class. In your
subclass you will need to override handler_conn_input as the default is to just
croak (it is a virtual method).

This module ISA L<POE::Class::Conn::Stream> which ISA L<POE::Class::Conn>. You
will want to see those modules for further details.

=head1 ACCESSORS

All accessors have three methods ala L<POE::Class::Attribs>. set_ATTRIB,
get_ATTRIB and ATTRIB. Set and get are obvious. ATTRIB is simply a set/get
method. See L<POE::Class::Attribs> for more details.

=over

=item path

The path to the UNIX socket file.

=back

=head1 METHODS

There are only two methods in this class. All other methods are inherited.

=over

=item new

This methods sets up internal data.

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



