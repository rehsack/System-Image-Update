package System::Image::Update::Role::HTTP;

use 5.014;
use strict;
use warnings FATAL => 'all';

use Moo::Role;
use Net::Async::HTTP;
use URI;
use HTTP::Status qw(status_message);

with "System::Image::Update::Role::Async", "System::Image::Update::Role::Logging";

our $VERSION = "0.001";

has http => ( is => "lazy" );

sub _build_http { my $http = Net::Async::HTTP->new(); $_[0]->loop->add($http); $http }

has http_user => ( is => "lazy" );

my $http_user_built;

sub _build_http_user
{
    my $eth0_info = qx(ip link show dev eth0);
    ( $http_user_built = $eth0_info =~ m,link/ether\s((?:[a-f0-9]{2}:){5}[a-f0-9]{2}),ms ? $1 : "" ) =~ s/://g;
    $http_user_built;
}

has http_passwd => ( is => "lazy" );

my $http_passwd_built;

sub _build_http_passwd
{
    my $eth0_info = qx(ip link show dev eth0);
    ( $http_passwd_built = $eth0_info =~ m,link/ether\s((?:[a-f0-9]{2}:){5}[a-f0-9]{2}),ms ? $1 : "" ) =~ s/://g;
    $http_passwd_built;
}

around collect_savable_config => sub {
    my $next                   = shift;
    my $self                   = shift;
    my $collect_savable_config = $self->$next(@_);

    my $http_user   = $self->http_user;
    my $http_passwd = $self->http_passwd;

    defined $http_user_built   or $collect_savable_config->{http_user}   = $self->http_user;
    defined $http_passwd_built or $collect_savable_config->{http_passwd} = $self->http_passwd;

    $collect_savable_config;
};

1;
