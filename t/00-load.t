#!perl -T
use 5.008003;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'System::Image::Update' ) || print "Bail out!\n";
}

diag( "Testing System::Image::Update $System::Image::Update::VERSION, Perl $], $^X" );
