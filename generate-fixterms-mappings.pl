#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use feature qw/say/;

my $presets_plist = "PresetKeyMappings.plist";
my $presets_data;
# generate some xml keybindings for iterm2 according to the 'fixterms'
# specification at http://www.leonerd.org.uk/hacks/fixterms/

# some handy constants.

sub CSI () { "\e[" }

sub SHIFT () { 1 }
sub ALT   () { 2 }
sub CTRL  () { 4 }

sub modifier_value {
    my (@modifiers) = @_;
    my $result = 1;
    $result += $_ for @modifiers;
    return $result == 1 ? '' : $result;
}

sub generate_CSI_u {
    my ($keycode, $modifiers) = @_;
    return sprintf('%s%d;%s%s', CSI, $keycode, $modifiers, 'u');
}

sub generate_CSI_tilde {
    my ($keycode, $modifiers) = @_;
    return sprintf('%s%d;%s%s', CSI, $keycode, $modifiers, '~');
}

sub generate_specials {
}


sub save_to_plist {
}

__END__

# TODO:
# * decode how key is specified in plist
# * write Data::Plist::XMLReader?
# * complete functions above.
# * Make it all work.
#
#
# sample of PresetKeyMappings plist
# <key>xterm Defaults</key> <-- name of preset
# <dict>
#	  <key>0xf700-0x260000</key> <- key, plus modifiers
#	  <dict>
#		  <key>Action</key>
#		  <integer>10</integer>	 <- 10 is 'send escape'
#		  <key>Text</key>
#		  <string>[1;6A</string> <- and the remaining sequence
#	  </dict>
#	  <key>0xf701-0x260000</key>
#	  <dict>
#		  <key>Action</key>
#		  <integer>10</integer>
#		  <key>Text</key>
#		  <string>[1;6B</string>
#	  </dict>
#	  <key>0xf702-0x260000</key>
#	  <dict>
#		  <key>Action</key>
#		  <integer>10</integer>
#		  <key>Text</key>
#		  <string>[1;6D</string>
#	  </dict>
# <dict>


# Modifiers:
# 
# Shift  : 0x020000 (Also affects the actual char)
# Ctrl   : 0x040000
# Option : 0x080000
# Cmd    : 0x100000

# Keys:


#"Keyboard Map" =		                  	  {
#		  "0x41-0x20000" = shift a				   {
#			  Action = 11;
#			  Text = "0x1 0x1";
#		  };
#		  "0x41-0xa0000" = 'shift meta a'		   {
#			  Action = 11;
#			  Text = "0x3 0x1";
#		  };
#		  "0x61-0x0" = 'a'				   {
#			  Action = 11;
#			  Text = 0x01;
#		  };
#		  "0x61-0x100000" = 'cmd a'					{
#			  Action = 11;
#			  Text = "0x8 0x1";
#		  };
#		  "0x61-0x40000" = 'ctrl a'				   {
#			  Action = 11;
#			  Text = "0x04 0x01";
#		  };
#		  "0x61-0x80000" = 'opt a'		   {
#			  Action = 11;
#			  Text = "0x2 0x1";
#		  };
#		  "0x62-0x0" = 'b'			   {
#			  Action = 11;
#			  Text = 0x2;
#		  };
#	  };

      "Keyboard Map" =             {
                "0x1b-0x0" =                 {
                    Action = 12;
                    Text = escape;
                };
                "0x41-0x20000" =                 {
                    Action = 11;
                    Text = "0x1 0x1";
                };
                "0x41-0xa0000" =                 {
                    Action = 11;
                    Text = "0x3 0x1";
                };
                "0x61-0x0" =                 {
                    Action = 11;
                    Text = 0x01;
                };
                "0x61-0x100000" =                 {
                    Action = 11;
                    Text = "0x8 0x1";
                };
                "0x61-0x40000" =                 {
                    Action = 11;
                    Text = "0x04 0x01";
                };
                "0x61-0x80000" =                 {
                    Action = 11;

                    Text = "0x2 0x1";
                };
                "0x62-0x0" =                 {
                    Action = 11;
                    Text = 0x2;
                };
                "0x7f-0x0" =                 {
                    Action = 12;
                    Text = backspace;
                };
                "0x9-0x0" =                 {
                    Action = 12;
                    Text = tab;
                };
                "0xf700-0x200000" =                 {
                    Action = 12;
                    Text = uparrow;
                };
                "0xf701-0x200000" =                 {
                    Action = 12;
                    Text = downarrow;
                };
                "0xf702-0x200000" =                 {
                    Action = 12;
                    Text = leftarrow;
                };
                "0xf703-0x200000" =                 {
                    Action = 12;
                    Text = rightarrow;
                };
                "0xf704-0x0" =                 {
                    Action = 12;
                    Text = f1;
                };
                "0xf705-0x0" =                 {
                    Action = 12;
                    Text = f2;
                };
                "0xf706-0x0" =                 {
                    Action = 12;
                    Text = f3;
                };
                "0xf707-0x0" =                 {
                    Action = 12;
                    Text = f4;
                };
                "0xf708-0x0" =                 {
                    Action = 12;
                    Text = f5;
                };
                "0xf709-0x0" =                 {
                    Action = 12;
                    Text = f6;
                };
                "0xf72c-0x0" =                 {
                    Action = 12;
                    Text = pgup;
                };
                "0xf72d-0x0" =                 {
                    Action = 12;
                    Text = pgdown;
                };
            };
