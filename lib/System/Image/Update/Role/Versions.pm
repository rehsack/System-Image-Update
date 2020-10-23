package System::Image::Update::Role::Versions;

use 5.014;
use strict;
use warnings FATAL => 'all';

=head1 NAME

System::Image::Update::Role::Versions - provides role for playing with versions

=cut

our $VERSION = "0.001";

use DateTime::Format::Strptime qw();
use File::Slurper qw(read_text);
use Module::Runtime qw(require_module);
use Scalar::Util qw/blessed/;
use version ();

use Moo::Role;

with "System::Image::Update::Role::Logging";

has month_by_name => (is => "lazy");

sub _build_month_by_name
{
    my @month_names = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    {
        map { $month_names[$_] => $_ + 1 } (0 .. $#month_names)
    }
}

has _depreciated_scanner => (is => "lazy");

sub _build__depreciated_scanner
{
    my $self = shift;
    DateTime::Format::Strptime->new(
        pattern  => "%FT%T",
        on_error => sub { $self->log->error($_[1]); 1 }
    );
}

sub _build_fake_ver
{
    my ($self, $dt) = @_;
    blessed $dt or $dt = $self->_depreciated_scanner->parse_datetime($dt);
    version->new("0.0." . $dt->epoch);
}

has installed_version_file => (
    is       => "ro",
    required => 1,
);

has installed_version => (
    is => "lazy",
);

sub _build_installed_version
{
    my $self = shift;
    -f $self->installed_version_file
      and return version->new((split("-", read_text($self->installed_version_file, chomp => 1)))[0]);

    require_module("File::LibMagic");
    my $kident = File::LibMagic->new()->describe_filename("/boot/uImage");
    $kident =~
      m,(Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\d+),
      or return $self->log->error("Can't extract kernel release date");
    my ($wday, $mon, $day, $hour, $minute, $second, $year, $kmatch) = ($1, $2, $3, $4, $5, $6, $7, $&);
    my $kdate = DateTime->new(
        year   => $year,
        month  => $self->month_by_name->{$mon},
        day    => $day,
        hour   => $hour,
        minute => $minute,
        second => $second,
    );

    my $fake_ver = $self->_build_fake_ver($kdate);
    $self->log->debug("Faking kernel build stamp $kmatch as version $fake_ver");
    $fake_ver;
}

=head1 AUTHOR

Jens Rehsack, C<< <rehsack at cpan.org> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2020-2016 Jens Rehsack.

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
