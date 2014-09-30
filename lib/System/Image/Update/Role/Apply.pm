package System::Image::Update::Role::Apply;

use 5.014;
use strict;
use warnings FATAL => 'all';

use Moo::Role;

use File::Copy qw(move);
use File::Path qw(make_path);

with "System::Image::Update::Role::Async", "System::Image::Update::Role::Logging";

our $VERSION = "0.001";

has image_location => (
    is      => "ro",
    default => "/data/.flashimg"
);
has flash_command => (
    is      => "ro",
    default => "/etc/init.d/flash-device.sh"
);

sub check4apply
{
    my $self = shift;

    $self->log->debug("Starting check4apply ...");
    $self->has_recent_update or return;

    if ( $self->recent_update->{apply} )
    {
        my $img_fn = $self->download_image;
        -e $img_fn or return $self->log->error("Cannot find $img_fn: $!");

        $self->wakeup_at( $self->recent_update->{apply}, "apply" );
    }
}

sub apply4real
{
    my $self = shift;

    make_path( $self->image_location );
    move( $self->download_image, $self->image_location )
      or return $self->log->error( "Cannot rename " . $self->download_image . " to " . $self->image_location . ": $!" );

    $self->reset_config;
    $self->save_config;

    system( $self->flash_command ) or return $self->log->error("Cannot send execute flash command: $!");
}

sub apply
{
    my $self = shift;

    $self->has_recent_update or return;

    $self->log->debug("Starting apply ...");
    $self->apply4real;

    # this path is passed in case of apply-error
    $self->reset_config;
    $self->save_config;

    return;
}

1;
