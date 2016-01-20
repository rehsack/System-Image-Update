package System::Image::Update::Role::Manifest;

use 5.014;
use strict;
use warnings FATAL => 'all';

=head1 NAME

System::Image::Update::Role::Manifest - provides role for handling manifest

=cut

our $VERSION = "0.001";

use File::Slurp::Tiny qw(read_file);
use JSON qw();
use version ();

use Moo::Role;

with "System::Image::Update::Role::Logging", "System::Image::Update::Role::Versions";

has manifest => (
    is      => "lazy",
    clearer => 1,
    trigger => 1,
);

sub _build_manifest
{
    $_[0]->clear_recent_manifest_entry;
    $_[0]->clear_available_images;

    my $mfcnt = read_file( $_[0]->update_manifest );
    JSON->new->decode($mfcnt);
}

sub _trigger_manifest
{
    $_[0]->clear_recent_manifest_entry;
    $_[0]->clear_available_images;
}

has recent_manifest_entry => (
    is      => "lazy",
    clearer => 1,
    trigger => 1,
);

sub _build_recent_manifest_entry
{
    my $self = shift;

    my ( $recent_key, $recent_ver );
    foreach my $avail_key ( keys %{ $self->manifest } )
    {
        my $avail_ver = eval { version->new($avail_key); };
        $@ and $avail_ver = $self->_build_fake_ver($avail_key);
        defined $recent_ver
          and $self->log->debug("Proving whether '$avail_ver' is more recent than currently chosen '$recent_ver'");
        defined $recent_ver and $recent_ver >= $avail_ver and next;
        defined $recent_ver and $self->log->debug("'$avail_ver' is more recent than '$recent_ver'");
        $recent_key = $avail_key;
        $recent_ver = $avail_ver;
    }
    $self->clear_available_images;
    +{ $recent_key => $self->manifest->{$recent_key} };
}

sub _trigger_recent_manifest_entry
{
    $_[0]->clear_available_images;
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
