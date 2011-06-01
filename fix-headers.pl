#!/usr/bin/env perl

use strict;
use warnings;
use feature qw/say/;

use File::Find;
use File::Copy;

my @DIRS = qw/Apps DVR Expose GTM Misc Popups Prefs
              Profiles Search Session Window/;

my $dir_match = { map { $_ => 1 } @DIRS };
my $headers;

find(\&find_headers, '.');
find(\&fix_imports, '.');





sub fix_imports {
    my $name = $_;
    my $path = $File::Find::name;
    my $dir  = $File::Find::dir;
#    say "Dir: $dir";
    $dir =~ s|^\./||;

    return unless exists $dir_match->{$dir};
    return unless $name =~ m/\.[mh]/;

    move($path, "$path.bak");
}


sub find_headers {
    my $name = $_;
    my $path = $File::Find::name;
    my $dir  = $File::Find::dir;
#    say "Dir: $dir";
    $dir =~ s|^\./||;

    return unless exists $dir_match->{$dir};
    return unless $name =~ m/\.h$/;

    #say "Found header: $_ in $dir";
    $headers->{$_} = $dir;

}
