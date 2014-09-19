package System::Image::Update::Role::Logging;

use Moo::Role;

use Class::Load qw(load_class);

with "MooX::Log::Any";

has log_adapter => (
    is       => "ro",
    required => 1,
    trigger  => 1
);

sub _trigger_log_adapter
{
    my ( $self, $opts ) = @_;
    load_class("Log::Any::Adapter")->set( @{$opts} );
}

1;
