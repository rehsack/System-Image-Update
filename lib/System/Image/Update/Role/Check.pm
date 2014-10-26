package System::Image::Update::Role::Check;

use 5.014;
use strict;
use warnings FATAL => 'all';

=head1 NAME

System::Image::Update::Role::Check - provides role for checking for updates

=cut

use Moo::Role;

use DateTime::Format::Strptime qw();
use File::LibMagic qw();
use File::Slurp::Tiny qw(read_file);

with "System::Image::Update::Role::Async", "System::Image::Update::Role::Logging", "System::Image::Update::Role::HTTP";

my @month_names = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
my %month_by_name = map { $month_names[$_] => $_ + 1 } ( 0 .. $#month_names );

sub check
{
    my $self = shift;
    $self->status("check");
    my $kident = File::LibMagic->new()->describe_filename("/boot/uImage");
    $kident =~
      m,(Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\d+),
      or return $self->log->error("Can't extract kernel release date");
    my ( $wday, $mon, $day, $hour, $minute, $second, $year, $kmatch ) = ( $1, $2, $3, $4, $5, $6, $7, $& );
    my $kdate = DateTime->new(
        year   => $year,
        month  => $month_by_name{$mon},
        day    => $day,
        hour   => $hour,
        minute => $minute,
        second => $second,
    );

    my $strp = DateTime::Format::Strptime->new(
        pattern  => "%FT%T",
        on_error => sub { $self->log->error( $_[1] ); 1 }
    );

    my $mfcnt    = read_file( $self->update_manifest );
    my $manifest = JSON->new->decode($mfcnt);

    my $recent_update;
    foreach my $avail_update ( sort keys %$manifest )
    {
        $self->log->debug("Proving whether $avail_update is newer than $kmatch");
        my $update_time = $strp->parse_datetime($avail_update);
        $update_time or next;
        $update_time->epoch > $kdate->epoch
          and $recent_update = $avail_update
          and $self->log->debug( "Applying because " . $update_time->epoch . " > " . $kdate->epoch );
    }
    $recent_update and $self->recent_update(
        {
            %{ $manifest->{$recent_update} },
            release_ts => $recent_update,
        }
    );
    $recent_update or $self->clear_recent_update;

    $recent_update;
}

=head1 AUTHOR

Jens Rehsack, C<< <rehsack at cpan.org> >>

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

1;
