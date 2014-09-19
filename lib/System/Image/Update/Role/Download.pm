package System::Image::Update::Role::Download;

use Moo::Role;
use 5.014;

with "System::Image::Update::Role::Async", "System::Image::Update::Role::Logging";

use File::Basename qw();
use File::Spec qw();

use Digest::SHA;
use Crypt::RIPEMD160;

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
    $self->{estimated_dl_ts} > $now
      and $self->wakeup_at( $self->{estimated_dl_ts}, "download" )
      and $self->scan_before( $self->{estimated_dl_ts} - 60 );
    $self->{estimated_dl_ts} <= $now and $self->wakeup_in( 1, "download" );
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
    looks_like_numer( $new_val->{release_ts} ) or $new_val->{release_ts} = $strp->parse_datetime( $new_val->{apply} )->epoch;
    my $release_ts = $new_val->{release_ts};
    if ( $new_val->{apply} )
    {
        looks_like_numer( $new_val->{apply} ) or $new_val->{apply} = $strp->parse_datetime( $new_val->{apply} )->epoch;

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
    -e $save_fn and unlink($save_fn);

    ($download_response_future) = $http->do_request(
        uri       => URI->new( $self->update_uri . $self->recent_update->{ $self->download_file } ),
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
    $download_response_future->cancel;
    $download_response_future = undef;
    -e $fn and unlink($fn);
    $self->clear_recent_update;
    $self->clear_download_image;
    $self->clear_download_sums;
    return $self->log->error($errmsg);
}

sub download_chunk
{
    my ( $self, $fn, $data ) = @_;

    $data or return $self->finish_download;

    my $fh;
    unless ( open( $fh, ">>", $fn ) )
    {
        return $self->abort_download( $fn, $! );
    }

    syswrite( $fh, $data ) or return $self->abort_download( $fn, "Cannot open $fn for appending: $!" );
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

    if ( defined( $save_chksum->{rmd160} ) )
    {
        my $fh;
        open( $fh, "<", $save_fn ) or return $self->abort_download( $save_fn, "Error opening $save_fn: $!" );

        my $context = Crypt::RIPEMD160->new;
        $context->reset();
        $context->addfile($fh);
        $string = $context->hexdigest();

        $string eq $save_chksum->{rmd160} or return $self->abort_download( $save_fn, "Invalid checksum for $save_fn" );
        ++$chksums_ok;
    }

    if ( defined( $save_chksum->{sha1} ) )
    {
        $sha = Digest::SHA->new("sha1");
        $sha->addfile($save_fn);
        my $string = $sha->hexdigest;

        $string eq $save_chksum->{sha1} or return $self->abort_download( $save_fn, "Invalid checksum for $save_fn" );
        ++$chksums_ok;
    }

    if ( defined( $save_chksum->{sha256} ) )
    {
        $sha = Digest::SHA->new("sha256");
        $sha->addfile($save_fn);
        my $string = $sha->hexdigest;

        $string eq $save_chksum->{sha256} or return $self->abort_download( $save_fn, "Invalid checksum for $save_fn" );
        ++$chksums_ok;
    }

    if ( defined( $save_chksum->{sha384} ) )
    {
        $sha = Digest::SHA->new("sha384");
        $sha->addfile($save_fn);
        my $string = $sha->hexdigest;

        $string eq $save_chksum->{sha384} or return $self->abort_download( $save_fn, "Invalid checksum for $save_fn" );
        ++$chksums_ok;
    }

    if ( defined( $save_chksum->{sha512} ) )
    {
        $sha = Digest::SHA->new("sha512");
        $sha->addfile($save_fn);
        my $string = $sha->hexdigest;

        $string eq $save_chksum->{sha512} or return $self->abort_download( $save_fn, "Invalid checksum for $save_fn" );
        ++$chksums_ok;
    }

    $chksums_ok >= 2 or return $self->abort_download( $self->download_image, "Not enought checksums passed" );
}

1;
