package POE::Class::Conn::Stream;

use POE::Class::Conn;
@ISA = qw(POE::Class::Conn);

use strict;

use POE qw/Wheel::ReadWrite/;

use Carp;

sub create_wheel {
    my $self = shift;
    croak "Unknown arguments passed to create_wheel()" if @_;

    $self->set_wheel(
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

1;

__END__

=head1 NAME

POE::Class::Conn::Stream - Base class for stream based connection classes

=head1 SYNOPSIS


    package POE::Class::Conn::FOOStream

    @POE::Class::Conn::FOOStream::ISA = qw(POE::Class::Conn::Stream);

    sub new {
        my $class = shift;

        my $self = $class->SUPER::new(@_);

        # do something interesting
    }

=head1 DESCRIPTION

An extremely simple class that simply overrides with C<create_wheel()> virtual method
in L<POE::Class::Conn> to create a L<POE::Wheel::ReadWrite> wheel for the connection.

You should look at L<POE::Class::Conn> for details on Connection Classes.

=head1 TODO

Write better documentation.

=head1 AUTHOR

Scott Beck E<lt>sbeck@gossamer-threads.comE<gt>

=head1 SEE ALSO

L<POE>
L<POE::Class>
L<POE::Class::Conn>

=cut


