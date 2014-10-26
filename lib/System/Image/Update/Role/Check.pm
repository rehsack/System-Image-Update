package System::Image::Update::Role::Check;

use 5.014;
use strict;
use warnings FATAL => 'all';

use Moo::Role;

use DateTime::Format::Strptime qw();
use File::LibMagic qw();
use File::Slurp::Tiny qw(read_file);

with "System::Image::Update::Role::Async", "System::Image::Update::Role::Logging", "System::Image::Update::Role::HTTP";

my @month_names = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
my %month_by_name = map { $month_names[$_] => $_ + 1 } ( 0 .. $#month_names );

sub check
{
    my $self = shift;
    $self->status("check");
    my $kident = File::LibMagic->new()->describe_filename("/boot/uImage");
    $kident =~
      m,(Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\d+),
      or return $self->log->error("Can't extract kernel release date");
    my ( $wday, $mon, $day, $hour, $minute, $second, $year, $kmatch ) = ( $1, $2, $3, $4, $5, $6, $7, $& );
    my $kdate = DateTime->new(
        year   => $year,
        month  => $month_by_name{$mon},
        day    => $day,
        hour   => $hour,
        minute => $minute,
        second => $second,
    );

    my $strp = DateTime::Format::Strptime->new(
        pattern  => "%FT%T",
        on_error => sub { $self->log->error( $_[1] ); 1 }
    );

    my $mfcnt    = read_file( $self->update_manifest );
    my $manifest = JSON->new->decode($mfcnt);

    my $recent_update;
    foreach my $avail_update ( sort keys %$manifest )
    {
        $self->log->debug("Proving whether $avail_update is newer than $kmatch");
        my $update_time = $strp->parse_datetime($avail_update);
        $update_time or next;
        $update_time->epoch > $kdate->epoch
          and $recent_update = $avail_update
          and $self->log->debug( "Applying because " . $update_time->epoch . " > " . $kdate->epoch );
    }
    $recent_update and $self->recent_update(
        {
            %{ $manifest->{$recent_update} },
            release_ts => $recent_update,
        }
    );
    $recent_update or $self->clear_recent_update;

    $recent_update;
}

1;
