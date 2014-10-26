package System::Image::Update::Role::Prove;

use 5.014;
use strict;
use warnings FATAL => 'all';

use Moo::Role;

with "System::Image::Update::Role::Async", "System::Image::Update::Role::Logging";

my %checksums = (
    rmd160 => sub {
        my $save_fn = shift;
        eval {
            require_module("Crypt::RIPEMD160");
            my $fh;
            open( $fh, "<", $save_fn ) or die "Error opening $save_fn: $!";
            seek( $fh, 0, 0 );
            my $context = Crypt::RIPEMD160->new;
            $context->reset();
            $context->addfile($fh);
            unpack( "H*", $context->digest() );
        };
    },
    sha1 => sub {
        my $save_fn = shift;
        eval {
            require_module("Digest::SHA");
            my $sha = Digest::SHA->new("sha1");
            $sha->addfile($save_fn);
            $sha->hexdigest;
        };
    },
    sha1_256 => sub {
        my $save_fn = shift;
        eval {
            require_module("Digest::SHA");
            my $sha = Digest::SHA->new("sha256");
            $sha->addfile($save_fn);
            $sha->hexdigest;
        };
    },
    sha1_384 => sub {
        my $save_fn = shift;
        eval {
            require_module("Digest::SHA");
            my $sha = Digest::SHA->new("sha384");
            $sha->addfile($save_fn);
            $sha->hexdigest;
        };
    },
    sha1_512 => sub {
        my $save_fn = shift;
        eval {
            require_module("Digest::SHA");
            my $sha = Digest::SHA->new("sha512");
            $sha->addfile($save_fn);
            $sha->hexdigest;
        };
    },
    md5 => sub {
        my $save_fn = shift;
        eval {
            require_module("Digest::MD5");
            my $md5 = Digest::MD5->new();
            my $fh;
            open( $fh, "<", $save_fn ) or die "Error opening $save_fn: $!";

            $md5->addfile($fh);
            $md5->hexdigest;
        };
    },
    md6 => sub {
        my $save_fn = shift;
        eval {
            require_module("Digest::MD6");
            my $md6 = Digest::MD6->new();
            my $fh;
            open( $fh, "<", $save_fn ) or return die "Error opening $save_fn: $!";

            $md6->addfile($fh);
            $md6->hexdigest;
        };
    },
);

sub prove
{
    my $self = shift;
    $self->has_recent_update or return $self->status("scan");
    my $save_fn     = $self->download_image;
    my $save_chksum = $self->download_sums;
    my $chksums_ok  = 0;

    # XXX silent prove? partial downloaded?
    -f $save_fn or return $self->status("scan");

    $self->status("prove");

    foreach my $chksum ( keys %$save_chksum )
    {
        defined $checksums{$chksum} and "CODE" eq ref $checksums{$chksum} and my $string = $checksums{$chksum}->($save_fn);
        $@ and $self->log->error($@);
        defined $string or next;    # kind of error ...

        # XXX $string might be undef here which causes a warning ...
        $string eq $save_chksum->{rmd160} or return $self->abort_download( $save_fn, "Invalid checksum for $save_fn" );
        ++$chksums_ok;
    }

    $chksums_ok >= 2 or return $self->abort_download( $self->download_image, "Not enought checksums passed" );
}

1;
