#!/usr/bin/env perl

use strict;
use warnings;
use feature qw/say/;

use File::Find;
use File::Copy;

my @DIRS = qw/App DVR Expose GTM Misc Popups Prefs
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
            say "Import line: $line";
            my $incfile = $1;
            my $incpath = $1;
            my $incdir  = $1;
            if ($incpath =~ m|^([^/]+)/(.+)|) {
                if (exists $headers->{$1}) {
                    say "already fixed. Not changing $1 / $2";
                    print $out_fh $line;
                    next;
                } elsif (exists $headers->{$2}) {
                    say "[$1 / $2] matched";
                    $incfile = $2;
                    my $new_dir = $headers->{$2};
                    say "incfile is $incfile, newdir: $new_dir";
                    #die "Couldn't find a header for $thing ($orig) on $line";
                    if ($new_dir) {
                        say "going to replace $incpath with $new_dir/$incfile";
                        print $out_fh "#import <$new_dir/$incfile>\n";
                    } else {
                        print $out_fh $line;
                    }
                } else {
                    print $out_fh $line;
                }
            } elsif (exists $headers->{$incpath}) {
                my $new_dir = $headers->{$incpath};
                say "fixing $new_dir / $incfile";
                print $out_fh "#import <$new_dir/$incfile>\n";
            } else {
                print $out_fh $line;
            }
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

sub confirm {
    my $input = <STDIN>;
    if ($input =~ m/[yY]/) {
        return 1;
    } else {
        return 0;
    }
}
