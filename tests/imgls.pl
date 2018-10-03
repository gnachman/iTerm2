#!/usr/bin/perl

# imgls: ls(1) listing supplemented with image thumbnails and image dimensions
#
#    Usage: imgls [--width #] [--height #] [--[no]par] [ls options] filename [filename]
#
# Writing an image to an iTerm window is fairly trivial; the bulk of this code handles features such
# as supporting ls(1) options, including recursion, supporting width and height image dimensions via
# command line, making the output pretty, and using faster Perl modules when available on the system.
#
# See function write_image() below to learn how to output an image, as per https://iterm2.com/images.html

use v5.14;
use strict;
use utf8;
use warnings;

use File::Basename;
use File::Which;
use Getopt::Long qw(:config no_permute pass_through require_order);
use IO::Handle;
use MIME::Base64;

# Use the faster Image::Size if available to calculate an image's size.
BEGIN {
    eval "require Image::Size";
}

STDERR->autoflush(1);
STDOUT->autoflush(1);
binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $prog = basename $0;

# some default values
my @lscmd  = qw/ls/;
my @lsopts = qw/-l -d/;                 # default ls(1) options
my %imgparams = (                       # default image option parameters
    height              => '3',         # character cells tall
    width               => '3',         # character cells wide
    inline              => '1',
    preserveAspectRatio => 'true',
);

# Encodes and outputs an image file to the window
#    arg 1: path to an image file
#
sub write_image {
    my $file = shift;

    # prepare the argument parameter list
    # add the name and size to the image argument parameter list
    $imgparams{'name'} = encode_base64($file, '');                              # file name is base64 encoded
    $imgparams{'size'} = (stat($file))[7];                                      # file size in bytes

    # write image data to STDERR so filters on STDOUT work as expected
    printf STDERR "%s%s%s;File=%s:%s%s",
            "\033", "]", "1337",                                                # image leadin sequence (OSC + 1337)
            join(';', map { $_ . '=' . $imgparams{$_} } keys %imgparams),       # semicolon separated pairs of param=value pairs
            encode_base64(get_image_bytes($file)),                              # base64 encoded image bytes
            "\007";                                                             # end-of-encoding char (BEL = ^G)
}

### main code 

my $php = which('php');
my $phpcmd = q/$a = getimagesize("$argv[1]"); if ($a==FALSE) exit(1); else { echo $a[0] . "x" .$a[1]; exit(0); }/;

# grab --width and --height command line options if they exist
my $result = GetOptions (
    "height=s" => \$imgparams{'height'},
    "width=s" => \$imgparams{'width'},
    "par!" => sub { $imgparams{'preserveAspectRatio'} = $_[1] ? 'true' : 'false' },
);
# grab any ls(1) options
while (@ARGV) {
    last unless $ARGV[0] =~ /^-/;
    push @lsopts, shift @ARGV;
}
push @ARGV, "." unless @ARGV;  # default to current directory if none provided

# don't recurse when no -R option supplied as an ls option
my $recurse = grep /R/, @lsopts;
my $lsa = grep /a/, @lsopts;

my $lines_output = 0;
my $nfiles = @ARGV;
while (@ARGV) {
    my $path = shift;

    if (! -e $path) {
        say "$prog: $path: No such file or directory";
        next;
    }

    if (-d $path) {
        my $dh;
        unless (opendir($dh, $path)) {
            say "Unable to open directory $path: $!";
            next;
        }

        if ($recurse or $nfiles > 1) {
            print "\n" if $lines_output;                        # output newline separator between directory headers, except first one
            print $path, ":\n";
        }
        while (readdir($dh)) {
            next if /^\./ and not $lsa;                         # skip dot files when -a is not specified
            if ($recurse and $_ !~ /^\.\.?$/ and -d "$path/$_") {
                push @ARGV, "$path/$_";                         # handle directory recursion - processed after files
            }
            do_ls_cmd("$path/$_");
        }
        closedir $dh;
    }
    else {
        do_ls_cmd("$path");
    }
    $lines_output++;
}

sub do_ls_cmd {
    my $file = shift;

    # Get the image dimensions to supplement the image and ls output.
    # Use Image::Size when available (non-stock), otherwise use PHP fallback method.
    my $dims;
    if (-e $file and -r $file) {
        if (Image::Size->can('imgsize')) {
            my ($w, $h) = Image::Size::imgsize($file);
            $dims = join 'x', $w, $h        if defined $w and defined $h;
        }
        elsif ($php) {
            $dims = get_cmd_output($php, '-r', $phpcmd, $file);
        }
    }
    if ($dims) {
        write_image $file;
        printf "%11s ", $dims;                                  # append the image's dimensions
    }
    else {
        printf "%s %11s ",
            ' ' x ($imgparams{'width'} =~ /^\d+$/ ?  $imgparams{'width'} : 3),
            ' ';
    }
    system @lscmd, @lsopts, $file;
}

sub usage {
    say "Usage: $prog [--width #] [--height #] [--[no]par] [ls options] filename [filename]";
    exit shift;
}

# grab the specified image file's contents
sub get_image_bytes {
    my $file = shift;

    $/ = undef;
    open (my $fh, "<", $file)
        or return undef;
    my $filebytes = <$fh>;
    chomp $filebytes;
    close $fh;

    return $filebytes;
}

sub get_cmd_output {
    my $prog = shift;

    use English;
    my ($ret, $pid);
    die "Can't fork: $!" unless defined($pid = open(KID, "-|"));
    if ($pid) {           # parent
        $ret .= $_       while <KID>;
        close KID;
        return $ret;
    }
    else {
        my @temp     = ($EUID, $EGID);
        my $orig_uid = $UID;
        my $orig_gid = $GID;
        $EUID = $UID;
        $EGID = $GID;
        # Drop privileges
        $UID  = $orig_uid;
        $GID  = $orig_gid;
        # Make sure privs are really gone
        ($EUID, $EGID) = @temp;
        die "Can't drop privileges"
            unless $UID == $EUID  && $GID eq $EGID;
        $ENV{PATH} = "/bin:/usr/bin"; # Minimal PATH.
    # Consider sanitizing the environment even more.
        exec $prog, @_,
            or warn "Failed to run $prog: $!";
    }
}

# vim: set expandtab
