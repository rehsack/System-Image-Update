package System::Image::Update;

use 5.014;
use strict;
use warnings FATAL => 'all';

our $VERSION = "0.001";

use IO::Async ();
use JSON      ();
use File::Basename qw(basename);
use File::Slurp::Tiny qw(write_file);
use File::ConfigDir ();
use File::ConfigDir::System::Image::Update qw(system_image_update_dir);
use namespace::clean;

use Moo;
use MooX::Options with_config_from_file => 1;

with "MooX::ConfigFromFile::Role::HashMergeLoaded";

with "System::Image::Update::Role::Async", "System::Image::Update::Role::Logging",
  "System::Image::Update::Role::Scan",     "System::Image::Update::Role::Check",
  "System::Image::Update::Role::Download", "System::Image::Update::Role::Prove",
  "System::Image::Update::Role::Apply";

=head1 NAME

System::Image::Update - helps managing updates of OS images in embedded systems

=head1 SYNOPSIS

    use System::Image::Update;

    System::Image::Update->new_with_options;

=head1 ATTRIBUTES

=head2 status

Lazy string contains the action to be executed next. Reasonably contains one of

=over 4

=item scan

See L<System::Image::Update::Role::Scan>

=item check

See L<System::Image::Update::Role::Check>

=item download

See L<System::Image::Update::Role::Download>

=item prove

See L<System::Image::Update::Role::Prove>

=item apply

See L<System::Image::Update::Role::Apply>

=back

To force a specific action, create a new object with an initializer for scan, eg.

    use System::Image::Update;

    System::Image::Update->new_with_options(status => "download");

or from outside:

    sed -e 's/{$/{"status": "check",/' /etc/sysimg_update.json
    svc -t /etc/daemontools/services/sysimg_update

=cut

has status => (
    is        => "rw",
    lazy      => 1,
    builder   => 1,
    predicate => 1,
    isa       => sub { __PACKAGE__->can( $_[0] ) or die "Invalid status: $_[0]" }
);

sub _build_status
{
    my $self   = shift;
    my $status = "scan";

    -f $self->update_manifest and $status = "check";
    $self->has_recent_update and -e $self->download_image and $status = "prove";

    return $status;
}

around BUILDARGS => sub {
    my $next   = shift;
    my $class  = shift;
    my $params = $class->$next(@_);

    $params->{status}
      and $params->{status} eq "apply"
      and $params->{status} = "prove";

          $params->{status}
      and $params->{status} eq "prove"
      and $params->{recent_update}
      and $params->{recent_update}->{apply} = DateTime->now->epoch;

    $params;
};

=head1 METHODS

=head2 run

starts the main loop after it initiates status build in case of guessing status.

=cut

sub run
{
    my $self = shift;
    my $cb   = $self->status;
    # that starts the regular scan interval
    $cb ne "scan" and $self->wakeup_in( 1, "scan" );
    $self->wakeup_in( 10, $cb );
    $self->loop->run;
}

=head2 collect_savable_config

routine being called when config saving is wanted

=cut

sub collect_savable_config
{
    my $self           = shift;
    my %savable_config = ();
    \%savable_config;
}

=head2 reset_config

routine being called to start fresh

=cut

sub reset_config
{
    my ( $self, $status ) = @_;
    $status or $self->schedule_scan;
    $self->wakeup_in( 1, "save_config" );
    $status and $self->wakeup_in( 1, $status );
}

has savable_configfile => ( is => "lazy" );

sub _build_savable_configfile
{
    my $self = $_[0];
    my ($scfd) = system_image_update_dir;
    defined $scfd and -d $scfd and return File::Spec->catfile( $scfd, basename( $self->config_files->[0] ) );
    $self->config_files->[0];
}

=head2 save_config

Saves result of L</collect_savable_config> in first file got via
L<MooX::ConfigFromFile|MooX::ConfigFromFile::Role/config_files>.

=cut

sub save_config
{
    my $self           = shift;
    my $savable_config = $self->collect_savable_config;
    my $savable_text   = JSON->new->pretty->allow_nonref->encode($savable_config);
    my $target         = $self->savable_configfile;
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

Copyright 2014-2016 Jens Rehsack.

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
