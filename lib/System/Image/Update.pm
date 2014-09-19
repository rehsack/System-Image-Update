package System::Image::Update;

use 5.014;
use strict;
use warnings FATAL => 'all';

our $VERSION = "0.001";

use Moo;
use MooX::Options with_config_from_file => 1;
use IO::Async ();
use JSON      ();
use File::Slurp::Tiny qw(write_file);

with "System::Image::Update::Role::Async", "System::Image::Update::Role::Logging", "System::Image::Update::Role::Scan",
  "System::Image::Update::Role::Download", "System::Image::Update::Role::Apply";

=head1 NAME

System::Image::Update - helps managing updates of OS images in embedded systems

=head1 SYNOPSIS

    use System::Image::Update;

    System::Image::Update->new_with_cmd;

=cut

has status => (
    is      => "rw",
    trigger => 1,
    isa     => sub { __PACKAGE__->can( $_[0] ) or die "Invalid status: $_[0]" }
);

sub _trigger_status
{
    my ( $self, $new_val ) = @_;
    my $cur_val = $self->status;
    $self->wakeup_in( 5, "save_config" );
}

sub run
{
    my $self = shift;
    my $cb   = $self->status;
    $self->check4update;
    $self->$cb;
    $self->loop->run;
}

sub collect_savable_config
{
    my $self = shift;
    my %savable_config = ( status => $self->status );
    \%savable_config;
}

sub save_config
{
    my $self           = shift;
    my $savable_config = $self->collect_savable_config;
    my $savable_text   = JSON->new->pretty->allow_nonref->encode($savable_config);
    my $target         = $self->config_files->[0];
    write_file( $target, $savable_text );    # XXX prove utf8 stuff
}

=head1 AUTHOR

Jens Rehsack, C<< <rehsack at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-system-image-update at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=System-Image-Update>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc System::Image::Update

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=System-Image-Update>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/System-Image-Update>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/System-Image-Update>

=item * Search CPAN

L<http://search.cpan.org/dist/System-Image-Update/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2014 Jens Rehsack.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut

1;    # End of System::Image::Update
