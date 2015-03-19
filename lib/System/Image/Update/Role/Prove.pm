package System::Image::Update::Role::Prove;

use 5.014;
use strict;
use warnings FATAL => 'all';

=head1 NAME

System::Image::Update::Role::Prove - provides role proving downloaded images

=cut

use File::stat;
use Module::Runtime qw(require_module);

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
    $self->has_recent_update or return $self->reset_config;
    my $save_fn     = $self->download_image;
    my $save_chksum = $self->download_sums;
    my $chksums_ok  = 0;

    # XXX silent prove? partial downloaded?
    -f $save_fn or return $self->schedule_scan;
    defined $save_chksum->{size}
      and stat($save_fn)->size != $save_chksum->{size}
      and return $self->abort_download( fallback_status => "check" );

    $self->status("prove");
    $self->wakeup_in( 1, "save_config" );

    foreach my $chksum ( keys %$save_chksum )
    {
        defined $checksums{$chksum} and "CODE" eq ref $checksums{$chksum} and my $string = $checksums{$chksum}->($save_fn);
        $@ and $self->log->error($@);
        defined $string or next;    # kind of error ...

        # XXX $string might be undef here which causes a warning ...
        $string eq $save_chksum->{$chksum} or return $self->abort_download( errmsg => "Invalid checksum for $save_fn" );
        ++$chksums_ok;
    }

    $chksums_ok >= 2 or return $self->abort_download( errmsg => "Not enought checksums passed" );

    $self->wakeup_in( 1, "check4apply" );
}

=head1 AUTHOR

Jens Rehsack, C<< <rehsack at cpan.org> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2014-2015 Jens Rehsack.

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
