package System::Image::Update::Role::Scan;

use 5.014;
use strict;
use warnings FATAL => 'all';

=head1 NAME

System::Image::Update::Role::Scan - role to scan for new updates

=cut

use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Slurp::Tiny qw(write_file);
use File::Spec;
use File::stat;
use HTTP::Status qw(status_message);
use URI;

use Moo::Role;

with "System::Image::Update::Role::Async", "System::Image::Update::Role::Logging", "System::Image::Update::Role::HTTP";

our $VERSION = "0.001";

my $default_update_server = "update.homepilot.de";
has update_server => (
    is      => "ro",
    default => $default_update_server,
);

my $default_update_path = "common";
has update_path => (
    is      => "ro",
    default => $default_update_path,
);

has scan_interval => (
    is      => "ro",
    default => 6 * 60 * 60,
);

my $default_update_manifest_basename = "manifest.json";
has update_manifest_basename => (
    is      => "ro",
    default => $default_update_manifest_basename,
);

my $default_update_manifest_dirname = $ENV{SYSTEM_IMAGE_UPDATE_DIR} // "/data/.update/";
has update_manifest_dirname => (
    is      => "ro",
    default => $default_update_manifest_dirname,
);

has update_manifest_uri => ( is => "lazy" );

sub _build_update_manifest_uri
{
    my $self = shift;
    my $u    = URI->new();
    $u->scheme("http");
    $u->host( $self->update_server );
    $u->path( File::Spec->catfile( $self->update_path, $self->update_manifest_basename ) );
    $u->as_string;
}

has update_manifest => (
    is => "lazy",
);

sub _build_update_manifest
{
    my $self = shift;
    File::Spec->catfile( $self->update_manifest_dirname, $self->update_manifest_basename );
}

around collect_savable_config => sub {
    my $next                   = shift;
    my $self                   = shift;
    my $collect_savable_config = $self->$next(@_);

    $self->update_server eq $default_update_server or $collect_savable_config->{update_server} = $self->update_server;
    $self->update_path eq $default_update_path     or $collect_savable_config->{update_path}   = $self->update_path;
    $self->update_manifest_dirname eq $default_update_manifest_dirname
      or $collect_savable_config->{update_manifest_dirname} = $self->update_manifest_dirname;
    $self->update_manifest_basename eq $default_update_manifest_basename
      or $collect_savable_config->{update_manifest_basename} = $self->update_manifest_basename;

    $collect_savable_config;
};

my $scan_timer;

sub scan_error
{
    my ( $self, $message ) = @_;
    $self->log->error( "Error fetching " . $self->update_manifest_uri . ": " . $message );
    $self->reset_config;
}

sub scan
{
    my ( $self, $extra_scan ) = @_;
    $self->log->debug("Starting scan ...");
    $extra_scan or $scan_timer = undef;
    $self->do_http_request(
        uri         => URI->new( $self->update_manifest_uri ),
        method      => "HEAD",
        on_response => sub { $self->check_newer_manifest(@_) },
        on_error    => sub { $self->scan_error(@_); },
    );
}

sub schedule_scan
{
    my $self = shift;
    $scan_timer and return;
    $self->status("scan");
    $scan_timer = $self->wakeup_in( $self->scan_interval, "scan" );
}

sub extra_scan { shift->scan(1); }

sub scan_before
{
    my ( $self, $ts ) = @_;

    $self->wakeup_in( $ts, "extra_scan" );
}

sub check_newer_manifest
{
    my ( $self, $response ) = @_;
    $response->code == 200 or return $self->scan_error( status_message( $response->code ) );

    my $manifest_mtime = -f $self->update_manifest ? stat( $self->update_manifest )->ctime : 0;
    my $manifest_last_modified = $response->last_modified || -1;

    $manifest_mtime < $manifest_last_modified and $self->do_http_request(
        uri         => URI->new( $self->update_manifest_uri ),
        method      => "GET",
        on_response => sub { $self->analyse_newer_manifest(@_) },
        on_error    => sub { $self->scan_error(@_); },
    );

    $self->schedule_scan;
}

sub analyse_newer_manifest
{
    my ( $self, $response ) = @_;
    $response->code == 200 or return $self->scan_error( status_message( $response->code ) );

    make_path( dirname( $self->update_manifest ) );
    write_file( $self->update_manifest, $response->content );
    $self->wakeup_in( 1, "save_config" );
    $self->wakeup_in( 1, "check" );
}

=head1 AUTHOR

Jens Rehsack, C<< <rehsack at cpan.org> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2014-2015 Jens Rehsack.

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
