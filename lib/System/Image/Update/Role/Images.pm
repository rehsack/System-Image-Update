package System::Image::Update::Role::Images;

use 5.014;
use strict;
use warnings FATAL => 'all';

=head1 NAME

System::Image::Update::Role::Images - provides the role for proving images

=cut

our $VERSION = "0.001";

use IO::Dir ();

use Moo::Role;

with "System::Image::Update::Role::Async", "System::Image::Update::Role::Logging";

use experimental 'smartmatch';

=head1 ATTRIBUTES

=head2 record_installed_location

...

=cut

has record_installed_location => (
    is      => "ro",
    default => "/opt/record-installed"
);

has record_installed => (
    is => "lazy",
);

sub _build_record_installed
{
    my $self = shift;
    my @installed;
    my $dir = IO::Dir->new( $self->record_installed_location );
    while ( defined( my $e = $dir->read ) )
    {
        push @installed, "$e" unless $e eq "." or $e eq "..";
    }
    \@installed;
}

has restrict_record_installed => (
    is       => "ro",
    required => 1
);
has record_installed_aliases => (
    is       => "ro",
    required => 1
);
has record_installed_components_image_separator => (
    is      => "ro",
    default => "+"
);

has installed_image => ( is => "lazy" );

sub _build_installed_image
{
    my $self = shift;

    my %a         = %{ $self->record_installed_aliases };
    my @img_comps = @{ $self->record_installed };
    my @rri       = @{ $self->restrict_record_installed };
    @img_comps = grep { !( $_ ~~ @rri ) } @img_comps;
    @img_comps = map { defined $a{$_} ? $a{$_} : $_ } @img_comps;

    join( $self->record_installed_components_image_separator, @img_comps );
}

has wanted_image => (
    is      => "lazy",
    trigger => 1
);

sub _build_wanted_image { $_[0]->installed_image }

sub _trigger_wanted_image
{
    my ( $self, $new ) = @_;
    my @a = @{ $self->available_images };
    $new ~~ @a or die $self->log->error( "$new is not in available images ['" . join( "', '", @a ) . "']" );
    $new;
}

has available_images => (
    is      => "lazy",
    clearer => 1
);

sub _build_available_images
{
    my $self = shift;

    my ( undef, $recent ) = %{ $self->recent_manifest_entry };
    my @avail;

    if ( my $dl_pfx = $self->download_file_prefix )
    {
        my $l = length $dl_pfx;
        @avail = map { substr $_, 0, $l, ""; $_ } grep { $dl_pfx eq substr $_, 0, $l } keys %{$recent};
    }
    else
    {
        while ( my ( $k, $v ) = each %{$recent} )
        {
            $v or next;
            my ( $file, @sums ) = split( ";", $v );
            @sums or next;
            push @avail, $k;
        }
    }

    [ sort @avail ];
}

around collect_savable_config => sub {
    my $next                   = shift;
    my $self                   = shift;
    my $collect_savable_config = $self->$next(@_);

    $self->wanted_image ne $self->installed_image and $collect_savable_config->{wanted_image} = $self->wanted_image;

    $collect_savable_config;
};

=head1 METHODS

=head1 AUTHOR

Jens Rehsack, C<< <rehsack at cpan.org> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2014-2016 Jens Rehsack.

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
