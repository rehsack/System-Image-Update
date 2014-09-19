package System::Image::Update::Role::Async;

use Moo::Role;

use IO::Async;
use IO::Async::Loop;

use IO::Async::Timer::Absolute;
use IO::Async::Timer::Countdown;

has loop => ( is => "lazy" );

sub _build_loop
{
    return IO::Async::Loop->new();
}

around collect_savable_config => sub {
    my $next                   = shift;
    my $self                   = shift;
    my $collect_savable_config = $self->$next(@_);
    $collect_savable_config->{log_adapter} = $self->log_adapter;
    $collect_savable_config;
};

sub wakeup_at
{
    my ( $self, $when, $cb_method ) = @_;

    my $timer = IO::Async::Timer::Absolute->new(
        time      => $when,
        on_expire => sub {
            $self->$cb_method;
        },
    );

    $self->loop->add($timer);
    $timer;
}

sub wakeup_in
{
    my ( $self, $in, $cb_method ) = @_;

    my $timer = IO::Async::Timer::Countdown->new(
        delay     => $in,
        on_expire => sub {
            $self->$cb_method;
        },
        remove_on_expire => 1,
    );

    $timer->start;
    $self->loop->add($timer);
    $timer;
}

1;
