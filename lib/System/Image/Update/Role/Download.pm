package System::Image::Update::Role::Download;

use Moo::Role;
use 5.014;

with "System::Image::Update::Role::Async", "System::Image::Update::Role::Logging";

use File::Basename qw();
use File::Spec qw();

use Module::Runtime qw(require_module);

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
    $self->wakeup_in( 5, "save_config" );
    my $now = DateTime->now->epoch;
    $new_val->{estimated_dl_ts} > $now
      and $self->wakeup_at( $new_val->{estimated_dl_ts}, "download" )
      and $self->scan_before( $new_val->{estimated_dl_ts} - 60 );
    $new_val->{estimated_dl_ts} <= $now and $self->wakeup_in( 1, "download" );
}

has download_file => (
    is      => "ro",
    default => "hp2"
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
    looks_like_number( $new_val->{release_ts} ) or $new_val->{release_ts} = $strp->parse_datetime( $new_val->{apply} )->epoch;
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

    $self->has_recent_update and $collect_savable_config->{recent_update} = $self->recent_update;

    $collect_savable_config;
};

my $download_response_future;

sub download
{
    my $self = shift;
    $download_response_future and return;
    $self->has_recent_update or return;
    $self->status("download");
    my $http = $self->http;

    # XXX skip download when image is already there and valid
    $self->prove_download and return $self->finish_download;

    my $save_fn = $self->download_image;
    # XXX add Content-Range as in http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.16
    #     and truncate file in that case ...
    -e $save_fn and unlink($save_fn);

    ($download_response_future) = $http->do_request(
        uri       => URI->new( $self->update_uri . $self->download_basename ),
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
    $self->status("scan");
    defined $download_response_future and $download_response_future->cancel;
    $download_response_future = undef;
    # -e $fn and unlink($fn);
    $self->clear_recent_update;
    $self->clear_download_image;
    $self->clear_download_basename;
    $self->clear_download_sums;
    return $self->log->error($errmsg);
}

sub download_chunk
{
    my ( $self, $fn, $data ) = @_;

    $data or return $self->finish_download;
    $self->log->notice( "Received " . length($data) . " bytes to save in $fn" );

    my $fh;
    unless ( open( $fh, ">>", $fn ) )
    {
        return $self->abort_download( $fn, $! );
    }

    syswrite( $fh, $data, length($data) ) or return $self->abort_download( $fn, "Cannot open $fn for appending: $!" );
    close($fh) or return $self->abort_download( $fn, $! );
}

sub finish_download
{
    my $self = shift;
    $self->prove_download or return;
    $self->check4apply;
}

sub prove_download
{
    my $self = shift;
    $self->has_recent_update or return;
    my $save_fn     = $self->download_image;
    my $save_chksum = $self->download_sums;
    my $chksums_ok  = 0;

    # XXX silent prove? partial downloaded?
    -f $save_fn or return;

    if ( defined( $save_chksum->{rmd160} ) )
    {
        my $string = eval {
            require_module("Crypt::RIPEMD160");
            my $fh;
            open( $fh, "<", $save_fn ) or return $self->abort_download( $save_fn, "Error opening $save_fn: $!" );

            seek( $fh, 0, 0 );
            my $context = Crypt::RIPEMD160->new;
            $context->reset();
            $context->addfile($fh);
            unpack( "H*", $context->digest() );
        };

        # XXX $string might be undef here which causes a warning ...
        $string eq $save_chksum->{rmd160} or return $self->abort_download( $save_fn, "Invalid checksum for $save_fn" );
        ++$chksums_ok;
    }

    if ( defined( $save_chksum->{sha1} ) )
    {
        my $string = eval {
            require_module("Digest::SHA");
            my $sha = Digest::SHA->new("sha1");
            $sha->addfile($save_fn);
            $sha->hexdigest;
        };

        # XXX $string might be undef here which causes a warning ...
        $string eq $save_chksum->{sha1} or return $self->abort_download( $save_fn, "Invalid checksum for $save_fn" );
        ++$chksums_ok;
    }

    if ( defined( $save_chksum->{sha1_256} ) )
    {
        my $string = eval {
            require_module("Digest::SHA");
            my $sha = Digest::SHA->new("sha256");
            $sha->addfile($save_fn);
            $sha->hexdigest;
        };

        # XXX $string might be undef here which causes a warning ...
        $string eq $save_chksum->{sha1_256} or return $self->abort_download( $save_fn, "Invalid checksum for $save_fn" );
        ++$chksums_ok;
    }

    if ( defined( $save_chksum->{sha1_384} ) )
    {
        my $string = eval {
            require_module("Digest::SHA");
            my $sha = Digest::SHA->new("sha384");
            $sha->addfile($save_fn);
            $sha->hexdigest;
        };

        # XXX $string might be undef here which causes a warning ...
        $string eq $save_chksum->{sha1_384} or return $self->abort_download( $save_fn, "Invalid checksum for $save_fn" );
        ++$chksums_ok;
    }

    if ( defined( $save_chksum->{sha1_512} ) )
    {
        my $string = eval {
            require_module("Digest::SHA");
            my $sha = Digest::SHA->new("sha512");
            $sha->addfile($save_fn);
            $sha->hexdigest;
        };

        # XXX $string might be undef here which causes a warning ...
        $string eq $save_chksum->{sha1_512} or return $self->abort_download( $save_fn, "Invalid checksum for $save_fn" );
        ++$chksums_ok;
    }

    if ( defined( $save_chksum->{md5} ) )
    {
        my $string = eval {

            require_module("Digest::MD5");
            my $md5 = Digest::MD5->new();
            my $fh;
            open( $fh, "<", $save_fn ) or return $self->abort_download( $save_fn, "Error opening $save_fn: $!" );

            $md5->addfile($fh);
            $md5->hexdigest;
        };

        # XXX $string might be undef here which causes a warning ...
        $string eq $save_chksum->{md5} or return $self->abort_download( $save_fn, "Invalid checksum for $save_fn" );
        ++$chksums_ok;
    }

    if ( defined( $save_chksum->{md6} ) )
    {
        my $string = eval {

            require_module("Digest::MD6");
            my $md6 = Digest::MD6->new();
            my $fh;
            open( $fh, "<", $save_fn ) or return $self->abort_download( $save_fn, "Error opening $save_fn: $!" );

            $md6->addfile($fh);
            $md6->hexdigest;
        };

        # XXX $string might be undef here which causes a warning ...
        $string eq $save_chksum->{md6} or return $self->abort_download( $save_fn, "Invalid checksum for $save_fn" );
        ++$chksums_ok;
    }

    $chksums_ok >= 2 or return $self->abort_download( $self->download_image, "Not enought checksums passed" );
}

1;
