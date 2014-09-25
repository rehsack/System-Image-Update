package System::Image::Update::Role::Apply;

use Moo::Role;

with "System::Image::Update::Role::Async", "System::Image::Update::Role::Logging";

our $VERSION = "0.001";

sub check4apply
{
    my $self = shift;

    $self->has_recent_update or return;

    if ( $self->recent_update->{apply} )
    {
        my $img_fn = File::Spec->catfile( $self->download_dir, $self->recent_update->{ $self->download_file } );
        -e $img_fn or return;

        $self->wakeup_at( $self->recent_update->{apply}, "apply" );
    }
}

sub apply
{
    my $self = shift;

    $self->has_recent_update or goto done;

    rename $self->download_image, "/data/flashimg/" and open( my $ath, "| at now" );
    ref $ath or return;
    print $ath "/bin/sh /etc/init.d/flash-device.sh\n";
    close $ath;

  done:
    return $self->status("scan");
}

1;
