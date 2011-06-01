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

    say "Processing $path";
    my $to = $name . '.bak';
    move($name, $to) or die "Failed to move $name to $to: $!";
    open my $in_fh, '<', $to or die "couldn't open $to to read: $!";
    open my $out_fh, '>', $name or die "couldn't open $name to write: $!";

    while (my $line = <$in_fh>) {
        if ($line =~ m|#import ["<]([^">]+)[">]|) {
            my $thing = $1;
            my $orig = $1;
            if ($thing =~ m|^([^/]+)(.*)+|) {
                if (exists $headers->{$1}) {
                    print $out_fh $line;
                    next;
                } else {
                    $thing = $2;
                }
            }
            my $new_dir = $headers->{$thing}
              or $orig; #die "Couldn't find a header for $thing ($orig) on $line";
            print $out_fh "#import <$new_dir/$1>\n";
        } else {
            print $out_fh $line;
        }
    }
    close $in_fh;
    close $out_fh;
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
