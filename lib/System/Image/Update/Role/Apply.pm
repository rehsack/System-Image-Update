package System::Image::Update::Role::Apply;

use 5.014;
use strict;
use warnings FATAL => 'all';

=head1 NAME

System::Image::Update::Role::Apply - provides the role for applying approved images

=cut

our $VERSION = "0.001";

use File::Copy qw(move);
use File::Path qw(make_path);

use Moo::Role;

with "System::Image::Update::Role::Async", "System::Image::Update::Role::Logging";

=head1 ATTRIBUTES

=head2 image_location

contains the location where the images for updating are located

=cut

has image_location => (
    is      => "ro",
    default => $ENV{SYSTEM_IMAGE_UPDATE_FLASH_DIR} // "/data/.flashimg"
);

=head2 flash_command

contains the command to be executed for applying update

=cut

has flash_command => (
    is      => "ro",
    default => "/etc/init.d/flash-device.sh"
);

=head1 METHODS

=head2 check4apply

checks when apply shall be invoked

=cut

sub check4apply
{
    my $self = shift;

    $self->log->debug("Starting check4apply ...");
    $self->has_recent_update or return;

    if ( $self->recent_update->{apply} )
    {
        my $img_fn = $self->download_image;
        -e $img_fn or return $self->log->error("Cannot find $img_fn: $!");

        my $now = DateTime->now->epoch;
        my $wait = $self->recent_update->{apply} - 60 > $now ? $self->recent_update->{apply} - $now : 1;
        $wait > 1 and $self->scan_before( $wait - 60 ) and $self->wakeup_in( $wait - 3, "prove" );
        $wait <= 1 and $self->wakeup_in( $wait, "apply" );
    }
}

sub _apply4real
{
    my $self = shift;

    make_path( $self->image_location );
    move( $self->download_image, $self->image_location )
      or return $self->log->error( "Cannot rename " . $self->download_image . " to " . $self->image_location . ": $!" );

    $self->reset_config;
    $self->save_config;

    # XXX svc -t (hp2sm) will abort flash!
    system( $self->flash_command ) or return $self->log->error("Cannot send execute flash command: $!");
}

=head2 apply

Applies the downloaded and proved image.

=cut

sub apply
{
    my $self = shift;

    $self->has_recent_update or return;

    $self->log->debug("Starting apply ...");
    $self->_apply4real;

    # this path is passed in case of apply-error
    $self->reset_config;
    $self->save_config;

    return;
}

=head1 AUTHOR

Jens Rehsack, C<< <rehsack at cpan.org> >>

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

1;
