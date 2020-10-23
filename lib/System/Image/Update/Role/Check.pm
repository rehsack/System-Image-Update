package System::Image::Update::Role::Check;

use 5.014;
use strict;
use warnings FATAL => 'all';

=head1 NAME

System::Image::Update::Role::Check - provides role for checking for updates

=cut

our $VERSION = "0.001";

use Moo::Role;

with "System::Image::Update::Role::Logging", "System::Image::Update::Role::Manifest", "System::Image::Update::Role::Versions";

sub _cmp_versions
{
    my ($self, $provided_version, $installed_version) = @_;
    $self->wanted_image eq $self->installed_image
      ? $provided_version > $installed_version
      : $provided_version >= $installed_version;
}

sub check
{
    my $self = shift;

    my $installed_version = $self->installed_version;

    $self->status("check");

    my ($provided_version, $recent_update) = %{$self->recent_manifest_entry};
    $self->log->debug("Proving whether '$provided_version' is more recent than installed '$installed_version'");
    $self->_cmp_versions(version->new($provided_version), $installed_version) or return $self->reset_config;
    $self->log->debug("'$provided_version' is more recent than '$installed_version'.");
    $self->recent_update({%{$recent_update}, (defined $recent_update->{release_ts} ? () : (release_ts => DateTime->now->epoch))});

    $recent_update;
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
