package System::Image::Update::Role::Scan;

use 5.014;
use strict;
use warnings FATAL => 'all';

use Moo::Role;

use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Slurp::Tiny qw(read_file write_file);
use File::Spec;
use File::stat;

with "System::Image::Update::Role::Async", "System::Image::Update::Role::Logging", "System::Image::Update::Role::HTTP";

our $VERSION = "0.001";

my $default_update_uri = "http://update.homepilot.de/common/";
has update_uri => (
    is      => "ro",
    default => $default_update_uri,
);

has scan_interval => (
    is      => "ro",
    default => 6 * 60 * 60,
);

my $default_update_manifest = "/data/.update/manifest.json";
has update_manifest => (
    is      => "ro",
    default => $default_update_manifest,
);

around collect_savable_config => sub {
    my $next                   = shift;
    my $self                   = shift;
    my $collect_savable_config = $self->$next(@_);

    $self->update_uri eq $default_update_uri           or $collect_savable_config->{update_uri}      = $self->update_uri;
    $self->update_manifest eq $default_update_manifest or $collect_savable_config->{update_manifest} = $self->update_manifest;

    $collect_savable_config;
};

my $scan_timer;

sub scan
{
    my ( $self, $extra_scan ) = @_;
    $self->log->debug("Starting scan ...");
    my $http = $self->http;
    $extra_scan or $scan_timer = undef;

    my ($response) = $http->do_request(
        uri         => URI->new( $self->update_uri . "manifest.json" ),
        method      => "HEAD",
        user        => $self->http_user,
        pass        => $self->http_passwd,
        on_response => sub { $self->check_newer_manifest(@_) }
    );
}

sub extra_scan { shift->scan(1); }

sub scan_before
{
    my ( $self, $ts ) = @_;

    my $now = DateTime->now->epoch;
    $ts > $now and $self->wakeup_at( $ts, "extra_scan" );
}

sub check_newer_manifest
{
    my ( $self, $response ) = @_;
    if ( $response->code != 200 )
    {
        $self->log->error( "Error fetching " . $self->update_uri . "manifest.json: " . status_message( $response->code ) );
        goto done;
    }

    my $manifest_mtime = -f $self->update_manifest ? stat( $self->update_manifest )->ctime : 0;
    my $manifest_last_modified = $response->last_modified || -1;

    if ( $manifest_mtime < $manifest_last_modified )
    {
        my $http = $self->http;
        my ($response) = $http->do_request(
            uri         => URI->new( $self->update_uri . "manifest.json" ),
            method      => "GET",
            user        => $self->http_user,
            pass        => $self->http_passwd,
            on_response => sub { $self->analyse_newer_manifest(@_) }
        );
    }

  done:
    $scan_timer or $scan_timer = $self->wakeup_in( $self->scan_interval, "scan" );
    return;
}

sub analyse_newer_manifest
{
    my ( $self, $response ) = @_;
    if ( $response->code != 200 )
    {
        $self->log->error( "Error fetching " . $self->update_uri . "manifest.json: " . status_message( $response->code ) );
        return;
    }

    make_path( dirname( $self->update_manifest ) );
    write_file( $self->update_manifest, $response->content );
    $self->wakeup_in( 1, "check" );
}

1;
