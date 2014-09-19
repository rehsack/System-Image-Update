package System::Image::Update::Role::Apply;

use Moo::Role;

with "System::Image::Update::Role::Async", "System::Image::Update::Role::Logging";

sub check4apply
{
    if ( $self->recent_update->{apply} )
    {
        my $img_fn = File::Spec->catfile( $self->download_dir, $self->recent_update->{ $self->download_file } );
        -e $img_fn or return;
    }
}

1;
