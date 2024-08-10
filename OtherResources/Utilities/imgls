#!/usr/bin/perl

# imgls: ls(1) listing supplemented with image thumbnails and dimensions
#
#    Usage: imgls [--width #] [--height #] [--[no]preserve_ratio]
#                 [--[no]dimensions] [--[no]unknown] [ls options] [file ...]
#
# Writing an image to an iTerm window is simple. See the official documentation
# at https://iterm2.com/documentation-images.html and the write_image() function below.
#
# Many of ls' options are supported, but not all.  The program does not support ls'
# default -C columnar output mode - output is always one entry per line.  Writing
# images across the page in columns appears to be problematic.
#
# In addition, options are available to specify setting image properties (width, height,
# preserve aspect ratio), include inline image dimensions, and disable output of
# generic icons for unsupported image types. Finally, a table-based image dimensions
# lookup mechanism is employed to obtain image dimensions.  It can call on Perl
# modules such as Image::Size, or call on external programs such as sips, mdls or php.
# It is easy to add additional entries to the table.  You can use the --method option
# to select any of the currently supported methods ('sips', 'mdls', 'php', and
# 'image::size').  These are tried, in that order; the first that appears to work
# is used for all.

use v5.14;
use strict;
use utf8;
use warnings;

use File::stat;
use IO::Select;
use IPC::Open3;
use File::Spec;
use MIME::Base64;
use File::Basename;
use Symbol 'gensym';
use Encode qw(decode);
use List::Util qw(max);
use POSIX qw(strftime floor modf);
use Getopt::Long qw(:config no_permute pass_through require_order);

STDERR->autoflush(1);
STDOUT->autoflush(1);
binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $prog = basename $0;
sub usage {
    my $leader = "usage: $prog";
    say STDERR
        "usage: $prog",
        " [--width #] [--height #] [--[no]preserve_ratio] [--[no]dimensions]",
        "\n",
        ' ' x length($leader),
        " [--[no]unknown] [ls options] [file ...]";

    exit shift;
}

# Some defaults
my $def_image_width     = 3;                    # height (in character cells)
my $def_image_height    = 1;                    # width  (in character cells)
my $def_preserve_ratio  = 'true';               # preserve aspect ratio

my %imgparams = (                               # default image option parameters
    inline              => 1,                   # image appears inline with text
    height              => $def_image_height,   # character cells tall
    width               => $def_image_width,    # character cells wide
    preserveAspectRatio => $def_preserve_ratio, # no stretchmarks please
);

my %failed_types;                               # cache of file extensions that have failed
my %stat_cache;                                 # cache of file/directory lstat() calls
my $curtime = time();
my $sixmonths = (365 / 2) * 86400;

my %opts = (
    height      => \$imgparams{'height'},
    width       => \$imgparams{'width'},
);
get_options(\%opts);

# find a method to obtain image dimensions
my $dims_methods = init_dims_methods();
my $dims_method  = find_dims_methods($dims_methods);

# single pixel image for non-renderable files
my ($one_pixel_black, $one_pixel_black_len) = get_black_pixel_image();

my $do_newline;
my $dot_filter = $opts{'A'} ? qr/^\.{1,2}$/ : qr/^\./;
$dot_filter    = undef          if $opts{'a'};

# special: empty @ARGV, or contains only '.'
my $do_header = @ARGV > 1 ? 1 : 0;
if (@ARGV <= 1) {
    push @ARGV, '.'     if @ARGV == 0;
}

my (@files, @dirs);
for (@ARGV) {
    if (! -e _lstat($_)) {
        say STDERR "$prog: $_: No such file or directory";
    }
    elsif (-f _lstat($_)) {
        push @files, $_;
    }
    else {
        push @dirs, $_;
    }
}
@files = ls_sort(@files);
@dirs  = ls_sort(@dirs);

if ($opts{'d'}) {
    push @files, @dirs;
    @dirs = ();
}
do_ls(undef, @files)    if @files;

while (@dirs) {
    my $path = shift @dirs;

    if (! -e $path) {
        say STDERR "$prog: $path: No such file or directory";
        next;
    }
    my (@f, @d);
    get_dir_content($path, $dot_filter, \@f, \@d) or
        next;
    do_ls($path, @f, @d);
    if ($opts{'R'}) {
        push @dirs, grep { ! /\.\.?$/ } @d;
    }
    $do_newline++;
}

# Encodes and outputs an image file to the window
#    arg 1: path to an image file
#    arg 2: size, in bytes, of the image
sub write_image {
    my ($file, $size) = @_;
    my $encoded;

    $imgparams{'name'} = encode_base64($file, '');                      # file name is base64 encoded
    $imgparams{'size'} = $size;                                         # file size in bytes

    if (ref $file eq '')  {
        my $bytes = get_image_bytes($file);
        $encoded = encode_base64($bytes)                if defined $bytes;
    }
    if (! $encoded or ref $file eq 'SCALAR') {
        $encoded = $one_pixel_black;
        $imgparams{'name'} = encode_base64('one_pixel_black', '');
        $imgparams{'size'} = $one_pixel_black_len;
    }

    printf "%s%s%s;File=%s:%s%s",
            "\033", "]", "1337",                                                # image leadin sequence (OSC + 1337)
            join(';', map { $_ . '=' . $imgparams{$_} } keys %imgparams),       # semicolon separated pairs of param=value pairs
            $encoded,                                                           # base64 encoded image bytes
            "\007";                                                             # end-of-encoding char (BEL = ^G)
}

sub get_options {
    local $SIG{__WARN__} = sub { say "$prog: ", $_[0]; usage(1) };
    Getopt::Long::Configure(qw/no_ignore_case bundling no_passthrough/);
    my $result = GetOptions(\%opts,
        'dimensions!'           => sub { $opts{'unknown'}++; $opts{$_[0]} = $_[1] },
        'height=s',
        'method=s',                                                             # use to force dimensions method
        "preserve_ratio!"       => sub { $imgparams{'preserveAspectRatio'} = $_[1] ? 'true' : 'false' },
        'unknown!'              => sub { $opts{'dimensions'}++; $opts{$_[0]} = $_[1] },
        'width=s',
        # supported ls options
        'D=s',
        't'                     => sub { delete $opts{'S'}; $opts{'t'}++ },
        'S'                     => sub { delete $opts{'t'}; $opts{'S'}++ },
        qw/ A F R T a d h i k l n o p r s u y /, 'c|U',
    );

    $opts{'d'} and delete $opts{'R'};
    $opts{'D'} and delete $opts{'T'};
    $opts{'n'} and $opts{'l'}++;
    $opts{'o'} and $opts{'l'}++;
    $opts{'s'} and $opts{'show_blocks'}++;
}

sub get_dir_content {
    my ($path, $filter, $filesref, $dirsref) = @_;
    my $dh;

    unless (opendir($dh, $path)) {
        say STDERR "Unable to open directory $path: $!";
        return undef;
    }

    while (readdir($dh)) {
        next if defined $filter and $_ =~ /$filter/;
        my $p = "$path/$_";
        if (-d _lstat($p)) {
            push @$dirsref, $p;
        }
        else {
            push @$filesref, $p;
        }
    }
    closedir $dh;
    return 1;
}

sub do_ls {
    my $path = shift;

    my $blocks_total = 0;
    my (@hfiles, %widths, $st);
    for my $file (ls_sort(@_)) {
        #say "FILE: $file";

        my %h;
        $h{'file'}      = $file;
        $h{'filename'}  = defined $path ? (split /\//, $file)[-1] : $file;
        $h{'st'}        = $st = _lstat($file);
        $h{'ino'}       = $st->ino                      if $opts{'i'};
        $h{'bytes'}     = $st->size;
        $h{'bytesh'}    = format_human($h{'bytes'})     if $opts{'h'};
        $h{'dims'}      = get_dimensions($file)         if $opts{'dimensions'} and -f $st && -r $st && $h{'bytes'};
        $h{'nlink'}     = $st->nlink                    if $opts{'s'} or $opts{'l'};

        if ($opts{'show_blocks'} or $opts{'l'}) {
            $h{'blocks'} = $st->blocks;
            if ( ! -d $st and ($opts{'a'} or $h{'filename'} !~ /^\.[^.]+/)) {
                $blocks_total += $st->blocks;
            }
        }

        if ($opts{'l'}) {
            $h{'lsmodes'} = Stat::lsMode::format_mode($st->mode);
            $h{'owner'} = ($opts{'n'} ? $st->uid : getpwuid $st->uid) // $st->uid;
            $h{'group'} = ($opts{'n'} ? $st->gid : getgrgid $st->gid) // $st->gid       if not $opts{'o'};
            $h{'time'}  = format_time($opts{'c'} ? $st->ctime : $st->mtime);
        }
        push @hfiles, \%h;

        $widths{'dim_w'}  = max(defined $h{'dims'} ? length($h{'dims'}{'width'})  : 0, $widths{'dim_w'} // 0);
        $widths{'dim_h'}  = max(defined $h{'dims'} ? length($h{'dims'}{'height'}) : 0, $widths{'dim_h'} // 0);
        for my $key (qw/blocks ino bytes bytesh owner group nlink/) {
            $widths{$key} = max(length($h{$key}), $widths{$key} // 0)   if exists $h{$key};
        }
    }

    # Header output when @ARGV was > 1, or after second dir
    print "\n"                                          if $path and $do_newline;
    print "$path:\n"                                    if $path and $do_header++;

    #   total blocks inline when -d, as header when -l or -s
    say "total ", $blocks_total / ($opts{'k'} ? 2 : 1)   if $path and ! $opts{'d'} and ($opts{'show_blocks'} or $opts{'l'});

    for my $h (@hfiles) {
        if (! -f $h->{'st'} or ! $h->{'bytes'} or ($opts{'dimensions'} and ! $h->{'dims'} and ! $opts{'unknown'})) {
            # pass a ref to indicate the data is already base64 encoded
            write_image \$one_pixel_black, $one_pixel_black_len;
        }
        else {
            write_image $h->{'file'}, $h->{'bytes'};
        }

        if ($opts{'dimensions'}) {
            if ($widths{'dim_w'} or $widths{'dim_h'}) {
                my $min_w = $widths{'dim_w'} // 1;
                my $min_h = $widths{'dim_h'} // 1;
                if ($h->{'dims'}{'width'} or $h->{'dims'}{'height'}) {
                    printf " [%*d x %*d] ", $min_w, $h->{'dims'}{'width'} // 0, $min_h, $h->{'dims'}{'height'} // 0;
                }
                else {
                    printf " %*s   %*s   ", $min_w, ' ', $min_h, ' ';
                }
            }
        }

        printf " %*d",  $widths{'ino'},    $h->{'ino'}                  if $opts{'i'};
        printf " %*d",  $widths{'blocks'}, $h->{'blocks'}               if $opts{'s'};
        printf " %s",   $h->{'lsmodes'}                                 if exists $h->{'lsmodes'};
        printf " %*s",  $widths{'nlink'},  $h->{'nlink'}                if exists $h->{'nlink'};
        printf " %*s",  $widths{'owner'},  $h->{'owner'}                if exists $h->{'owner'};
        printf "  %*s", $widths{'group'},  $h->{'group'}                if exists $h->{'group'};
        if ($opts{'l'}) {
            printf "  %*d", $widths{'bytes'},  $h->{'bytes'}            if ! $opts{'h'};
            printf "  %4s", $h->{'bytesh'}                              if $opts{'h'};
        }
        printf " %s",   $h->{'time'}                                    if exists $h->{'time'};
        print  " ",     Encode::decode('UTF-8', defined $path ? (split /\//, $h->{'file'})[-1] : $h->{'file'});
        printf "%s",    get_F_type($h->{'st'})                          if $opts{'F'} or $opts{'p'};
        print "\n";
    }
}

# Get the image's dimensions to supplement the image and ls output.
sub get_dimensions {
    my $file = shift;

    my ($ret, $ext);
    $file =~ /\.([^.]+)$/ and $ext = $1;

    if ($dims_method and (!$ext or ($ext and ! exists $failed_types{$ext}))) {
        if (ref $dims_method->{'prog'} eq 'CODE') {
            $ret = $dims_method->{'format'}->($file);
        }
        else {
            my ($stdout, $stderr, $exit) = runcmd($dims_method->{'prog'}, @{$dims_method->{'args'}}, $file);
            if ($stdout) {
                $ret = $dims_method->{'format'}->($stdout);
            }
        }
    }

    $failed_types{$ext}++       if ! $ret and $ext;
    return $ret;
}

sub runcmd {
    my $prog = shift;

    my $pid = open3(my $in, my $out, my $err = gensym, $prog, @_);

    my ($out_buf, $err_buf) = ('', '');
    my $select = new IO::Select;
    $select->add($out, $err);
    while (my @ready = $select->can_read(5)) {
        foreach my $fh (@ready) {
            my $data;
            my $bytes = sysread($fh, $data, 1024);
            if (! defined( $bytes) && ! $!{ECONNRESET}) {
                die "error running cmd: $prog: $!";
            }
            elsif (! defined $bytes or $bytes == 0) {
                $select->remove($fh);
                next;
            }
            else {
                if    ($fh == $out) { $out_buf .= $data; }
                elsif ($fh == $err) { $err_buf .= $data; }
                else {
                    die 'unexpected filehandle in runcmd';
                }
            }
        }
    }

    waitpid($pid, 0);
    return ($out_buf, $err_buf, $? >> 8);
}

# List of methods to obtain image dimensions, tried in prioritized order.
# Can be external programs or perl module.  Expected to return undef when no
# dimensions can be found, or a hash ref with 'width' and 'height' elements.
sub init_dims_methods {
    return [
        {
            prog        => 'sips',
            args        => [ '-g', 'pixelWidth', '-g', 'pixelHeight' ],
            format      => sub {
                my $out = shift;
                return ($out =~ /pixelWidth: (\d+)\s+pixelHeight: (\d+)/s) ? { width => $1, height => $2 } : undef;
            }
        },

        {
            prog        => 'mdls',
            args        => [ '-name', 'kMDItemPixelWidth', '-name', 'kMDItemPixelHeight' ],
            format      => sub {
                my $out = shift;
                my %dim;
                for my $d (qw /Width Height/) {
                    $dim{$d} = $1               if $out =~ /kMDItemPixel$d\s*=\s*(\d+)$/m;
                }
                return ($dim{'Width'} and $dim{'Height'}) ? { width => $dim{'Width'}, height => $dim{'Height'} } : undef;
            }
        },

        {
            prog        => 'php',
            args        => [ '-r', q/$a = getimagesize("$argv[1]"); if ($a==FALSE) exit(1); else { echo $a[0] . "x" .$a[1]; exit(0); }/ ],
            format      => sub {
                my $out = shift;
                return undef unless $out;
                my @d = split /x/, $out;
                return { width => $d[0], height => $d[1] };
            }
        },

        {
            prog        => 'exiftool',
            args        => [ '-s', '-ImageSize' ],
            format      => sub {
                my $out = shift;
                return ($out =~ /ImageSize\s+:\s+(\d+)x(\d+)/) ? { width => $1, height => $2 } : undef;
            }
        },

        # Use Image::Size last, due to limitations mentioned elsewhere
        {
            prog        => \&have_Image_Size,
            format      => \&call_Image_Size,
            name        => 'Image::Size',
        }
    ]
};

# Look for a dims_methods program to determine image dimensions
sub find_dims_methods {
    my $methods = shift;

    if ($opts{'method'}) {
        @$methods = grep {
            (exists $_->{'name'} and (lc($_->{'name'}) eq lc($opts{'method'}))) or
            ($_->{'prog'} eq $opts{'method'}) } @$methods;
    }

    for (@$methods) {
        if (ref $_->{'prog'} eq 'CODE' and $_->{'prog'}->()) {
            return $_;
        }
        elsif (my $choice = which($_->{'prog'})) {
            $_->{'prog'} = $choice;
            return $_;
        }
    }

    say STDERR "$prog: no methods found to obtain image dimensions. Tried: ",
        map { "\n   " . (exists $_->{'name'} ? $_->{'name'} : $_->{'prog'}) } @$methods;

    exit 1;
}

# Allow Image::Size to be used if available to calculate an image's size.  It
# does not support dimensions of PDF files, so it will be tried last.
sub have_Image_Size {
    eval "require Image::Size";
    return Image::Size->can('imgsize');
}

sub call_Image_Size {
    my $file = shift;

    my ($w, $h, $type) = Image::Size::imgsize($file);
    if (defined $w and defined $h) {
        # Bug: Workaround negative BMP size values, discovered with export to BMP via
        # SnagIt and Pixelmator (classic).
        if ($type eq 'BMP') {                   
            $w = (2**32) - $w   if $w > 2**31;
            $h = (2**32) - $h   if $h > 2**31;
        }
        return { width => $w, height => $h };
    }

    return undef;
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

sub ls_sort {
    return if ! (@_ or scalar @_ > 1);

    if ($opts{'t'}) {
        # descending
        @_ = ($opts{'y'} or $ENV{'LS_SAMESORT'}) ?
            sort { _lstat($b)->mtime <=> _lstat($a)->mtime || $b cmp $a } @_ :
            sort { _lstat($b)->mtime <=> _lstat($a)->mtime || $a cmp $b } @_;
    }
    # macOS seems to sort lexically with -c/-U, but shows ctime timestamps
    elsif ($opts{'c'}) {
        @_ = sort { $a cmp $b } @_;
    }
    elsif ($opts{'u'}) {
        @_ = sort { _lstat($a)->atime <=> _lstat($b)->atime } @_;
    }
    elsif ($opts{'S'}) {
        @_ = sort { _lstat($b)->size <=> _lstat($a)->size || $a cmp $b } @_;
    }
    else {
        @_ = sort @_;
    }

    return $opts{'r'} ? reverse @_ : @_;
}

sub get_F_type {
    my $st = shift;

    return '/'  if -d $st and ($opts{'p'} or $opts{'F'});
    return ''   unless $opts{'F'};
    return '@'  if -l $st;
    return '|'  if -p $st;
    return '='  if -S $st;
    return '*'  if -x $st;      # must come after other tests
    return '';
}

sub format_time {
    my $time = shift;

    my $fmt;
    if ($opts{'D'}) {
        $fmt = $opts{'D'};
    }
    elsif ($opts{'T'}) {
        # mmm dd hh:mm:ss yyyy
        $fmt = '%b %e %T %Y';
    }
    else {
        if ($time + $sixmonths > $curtime and $time < $curtime + $sixmonths) {
            # mmm dd hh:mm
            $fmt = '%b %e %R';
        }
        else {
            # mmm dd  yyyy
            $fmt = '%b %e  %Y';
        }
    }
    return strftime $fmt, localtime($time);
}

sub format_human {
    my $bytes = shift;

    my @units = ('B', 'K', 'M', 'G', 'T', 'P');
    my $scale = floor((length($bytes) - 1) / 3);
    my $float = $bytes / (1024 ** $scale);

    my ($frac, $int) = modf($float);
    if (length($bytes) < 3 or length($int) >= 2) {
        sprintf "%d%s", $frac <.5 ? $float : $float + 1, $units[$scale];
    }
    else {
        sprintf "%.1f%s", $float, $units[$scale];
    }
}

sub _lstat {
    my $file = shift;
    return $stat_cache{$file}   if exists $stat_cache{$file};

    if (my $s = lstat($file)) {
        return $stat_cache{$file} = $s;
    }

    return $file;
}

sub which {
  my ($exec) = @_;

    $exec or
        return undef;

    if ($exec =~ m#/# && -f $exec && -x _) {
        return $exec
    }

    foreach my $file ( map { File::Spec->catfile($_, $exec) } File::Spec->path) {
        -d $file and
            next;
        -x _ and
            return $file;
    }

    return undef;
}


# Generate 1 pixel black PNG as placeholding for non-image-able files.
sub get_black_pixel_image {
    # base 64 encoded single black pixel png
    my $one_pixel_black = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIW2NgYGD4DwABBAEAwS2OUAAAAABJRU5ErkJggg==';
    return ($one_pixel_black, length $one_pixel_black);
}

# Based on Stat::lsMode, Copyright 1998 M-J. Dominus, (mjd-perl-lsmode@plover.com)
# You may distribute this module under the same terms as Perl itself.

package Stat::lsMode;

sub format_mode {
    my $mode = shift;

    return undef        unless defined $mode;

    my @permchars  = qw(--- --x -w- -wx r-- r-x rw- rwx);
    my @ftypechars = qw(. p c ? d ? b ? - ? l ? s ? ? ?);
    $ftypechars[0] = '';

    my $setids     = ($mode & 07000) >> 9;
    my @permstrs   = @permchars[($mode & 0700) >> 6, ($mode & 0070) >> 3, $mode & 0007];
    my $ftype      = $ftypechars[($mode & 0170000) >> 12];

    if ($setids) {
        if ($setids & 01) {             # sticky
            $permstrs[2] =~ s/([-x])$/$1 eq 'x' ? 't' : 'T'/e;
        }
        if ($setids & 04) {             # setuid
            $permstrs[0] =~ s/([-x])$/$1 eq 'x' ? 's' : 'S'/e;
        }
        if ($setids & 02) {             # setgid
            $permstrs[1] =~ s/([-x])$/$1 eq 'x' ? 's' : 'S'/e;
        }
    }

    join '', $ftype, @permstrs;
}

# vim: expandtab
