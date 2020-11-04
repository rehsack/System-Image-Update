package System::Image::Update::Role::Prove;

use 5.014;
use strict;
use warnings FATAL => 'all';

=head1 NAME

System::Image::Update::Role::Prove - provides role proving downloaded images

=cut

use Capture::Tiny qw(capture);
use File::stat;
use Module::Runtime qw(require_module);

use Moo::Role;

with "System::Image::Update::Role::Async", "System::Image::Update::Role::Logging";

has prove_exec => (
    is       => "ro",
    required => 1,
);

has verified_update => (
    is        => "rwp",
    predicate => 1,
    clearer   => 1,
    init      => undef,
);

sub prove
{
    my $self = shift;
    $self->has_recent_update or return $self->reset_config;
    my $save_fn = $self->download_image;

    # XXX silent prove? partial downloaded?
    -f $save_fn or return $self->schedule_scan;
    my ($stdout, $stderr, $exit) = capture
    {
        my $cmd = join(" ", $self->prove_exec, $save_fn);
        system($cmd);
    };

    $exit == 0 or return $self->abort_download(errmsg => "Not enought checksums passed");

    $self->_set_verified_update($self->recent_update);

    $self->wakeup_in(1, "check4apply");
}

=head1 AUTHOR

Jens Rehsack, C<< <rehsack at cpan.org> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2014-2020 Jens Rehsack.

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
