package System::Image::Update::Role::Download;

use 5.014;
use strict;
use warnings FATAL => 'all';

=head1 NAME

System::Image::Update::Role::Download - role for downloading most recent update

=cut

use Moo::Role;

with "System::Image::Update::Role::Async", "System::Image::Update::Role::Logging";

use File::Basename qw();
use File::Spec qw();

use Scalar::Util qw(looks_like_number);

our $VERSION = "0.001";

has recent_update => (
    is        => "rw",
    trigger   => 1,
    predicate => 1,
    clearer   => 1,
);

sub _trigger_recent_update
{
    my ( $self, $new_val ) = @_;
    exists $new_val->{estimated_dl_ts} or $self->determine_estimated_dl_ts($new_val);
    $self->wakeup_in( 1, "save_config" );
    my $now = DateTime->now->epoch;
    $new_val->{estimated_dl_ts} > $now
      and $self->wakeup_at( $new_val->{estimated_dl_ts}, "download" )
      and $self->scan_before( $new_val->{estimated_dl_ts} - 60 );
    $new_val->{estimated_dl_ts} <= $now and $self->wakeup_in( 1, "download" );
}

my $default_download_file = -x "/imx6/xbmc/bin/xbmc" ? "hp2+xbmc" : "hp2";
has download_file => (
    is      => "ro",
    default => $default_download_file,
);

has min_download_wait => (
    is      => "ro",
    default => 8 * 24 * 3600
);
has max_download_wait => (
    is      => "ro",
    default => 11 * 24 * 3600
);

has download_dir => ( is => "lazy" );

sub _build_download_dir { File::Basename::dirname( $_[0]->update_manifest ); }

has download_basename => (
    is      => "lazy",
    clearer => 1
);

sub _build_download_basename
{
    my $self = shift;
    $self->has_recent_update or die "No downloadable image without a recent update";
    my $save_fn = $self->recent_update->{ $self->download_file };
    $save_fn = ( split ";", $save_fn )[0];
}

has download_image => (
    is      => "lazy",
    clearer => 1
);

sub _build_download_image
{
    my $self = shift;
    $self->has_recent_update or die "No downloadable image without a recent update";
    my $save_fn = $self->recent_update->{ $self->download_file };
    $save_fn = ( split ";", $save_fn )[0];
    $save_fn = File::Spec->catfile( $self->download_dir, $save_fn );
    $save_fn;
}

has download_sums => (
    is      => "lazy",
    clearer => 1
);

sub _build_download_sums
{
    my $self      = shift;
    my $save_fn   = $self->recent_update->{ $self->download_file };
    my @save_info = split ";", $save_fn;
    shift @save_info;
    my %sums = map { split "=", $_, 2 } @save_info;
    \%sums;
}

sub determine_estimated_dl_ts
{
    my ( $self, $new_val ) = @_;

    my $strp = DateTime::Format::Strptime->new(
        pattern  => "%FT%T",
        on_error => sub { $self->log->error( $_[1] ); 1 }
    );
    looks_like_number( $new_val->{release_ts} )
      or $new_val->{release_ts} = $strp->parse_datetime( $new_val->{release_ts} )->epoch;
    my $release_ts = $new_val->{release_ts};
    if ( $new_val->{apply} )
    {
        looks_like_number( $new_val->{apply} ) or $new_val->{apply} = $strp->parse_datetime( $new_val->{apply} )->epoch;

        my $apply_ts      = $new_val->{apply};
        my $delta_seconds = $apply_ts - $release_ts;
        $delta_seconds > 0 and $new_val->{estimated_dl_ts} = $release_ts + int( $delta_seconds / ( ( rand 20 ) + 21 ) );
        $new_val->{estimated_dl_ts} //= 1;
    }
    else
    {
        $new_val->{estimated_dl_ts} =
          $release_ts + rand( $self->max_download_wait - $self->min_download_wait ) + $self->max_download_wait + 1;
    }
}

around collect_savable_config => sub {
    my $next                   = shift;
    my $self                   = shift;
    my $collect_savable_config = $self->$next(@_);

    $self->has_recent_update                       and $collect_savable_config->{recent_update} = $self->recent_update;
    $self->download_file ne $default_download_file and $collect_savable_config->{download_file} = $self->download_file;

    $collect_savable_config;
};

around reset_config => sub {
    my $next = shift;
    my $self = shift;
    $self->$next(@_);

    $self->clear_download_image;
    $self->clear_download_basename;
    $self->clear_download_sums;
    $self->clear_recent_update;

    return;
};

my $download_response_future;

sub download
{
    my $self = shift;
    $self->log->debug("Starting download ...");
    $download_response_future and return;
    $self->has_recent_update or return;
    $self->status("download");
    my $http = $self->http;

    # XXX skip download when image is already there and valid
    -f $self->download_image and $self->prove and return;

    my $save_fn = $self->download_image;
    # XXX add Content-Range as in http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.16
    #     and truncate file in that case ...
    -e $save_fn and unlink($save_fn);

    my $u = URI->new();
    $u->scheme("http");
    $u->host( $self->update_server );
    $u->path( File::Spec->catfile( $self->update_path, $self->download_basename ) );
    ($download_response_future) = $http->do_request(
        uri       => $u,
        method    => "GET",
        user      => $self->http_user,
        pass      => $self->http_passwd,
        on_header => sub {
            return sub { $self->download_chunk( $save_fn, @_ ) }
        }
    );
}

sub abort_download
{
    my ( $self, $fn, $errmsg ) = @_;
    $self->log->debug("Aborting download ...");
    $self->status("scan");
    defined $download_response_future and $download_response_future->cancel;
    $download_response_future = undef;
    -e $fn and unlink($fn);
    $self->reset_config;

    return $self->log->error($errmsg);
}

sub download_chunk
{
    my ( $self, $fn, $data ) = @_;

    $data or return $self->finish_download;

    my $fh;
    open( $fh, ">>", $fn ) or return $self->abort_download( $fn, "Cannot open $fn for appending: $!" );

    syswrite( $fh, $data, length($data) ) or return $self->abort_download( $fn, "Cannot append to $fn: $!" );
    close($fh) or return $self->abort_download( $fn, "Error closing $fn: $!" );
}

sub finish_download
{
    my $self = shift;
    $self->log->debug("Starting finish_download ...");
    $self->wakeup_in( 1, "prove" );
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
