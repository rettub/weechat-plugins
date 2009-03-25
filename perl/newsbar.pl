# -----------------------------------------------------------------------------
#
# TONS OF THANKS TO FlashCode FOR HIS IRC CLIENT AND HIS SUPPORT ON #weechat
#
# -----------------------------------------------------------------------------
# Copyright (c) 2009 by rettub <rettub@gmx.net>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# -----------------------------------------------------------------------------
# newsbar for weechat version 0.2.7 or later
#
# Listens for highlights and sends them to a bar.
#
#
# Usage:
#
#  Simply load the script, and all highlights in all channels will be sent to a
#  bar.
#
#  Simple commands:
#  /newsbar always         enable highlights to bar always.
#  /newsbar away_only      enable highlights to bar if away only
#  /newsbar clear [regexp] clears the bar optional with perl regexp
#  /newsbar memo [text]    writes text into the script's bar
#  /newsbar add text       text formatted the script's bar
#
# Configuration:
#
#  away_only:              collect hihlights only if away isn't set
#  show_highlights         Enable/disable handling of public messages
#  show_priv_msg           Enable/disable handling of private messages
#  show_priv_server_msg    Enable/disable handling of private server messages
#  format_public :         format-string for public highlights
#  format_private:         format-string for private highlights
#                          %n : nick,    %N : colored nick
#                          %c : channel, %C : colored channel
#                          %s : server
#  memo_tag_color          Color of '[memo]'
#  remove_bar_on_unload    Remove bar when script will be unloaded. 
#  bar_auto_hide           Hide bar if empty.
#  bar_hidden_on_start     Start with a hidden bar.
#  bar_visible_lines       lines visible if bar is shown.
#  bar_seperator           Show bar separator line.
#  bar_title               Title of info bar
#
#  debug:                  Show some debug/warning messages on failture
#
# -----------------------------------------------------------------------------
# XXX Known bugs:
#     Bar must be redrawed if terminal size has changed (wrapping)
#     Wrapping starts to early if some locale/utf chars contained in message string
# 
# More bugs? Would be surprised if not, please tell me!
#
# -----------------------------------------------------------------------------
# TODO Optional execute an external user cmd with args:
#        nick, channel, server, message, ... (date/time?)
#      Or write a special script for it.
#      Can be uesed for scripts using libnotify, make weechat speaking to you
#      (I use festival for it)
# TODO exclude nicks, channels, servers, ... by eg. user defined whitelists
#      and/or blacklists
# TODO newsbeuter
# -----------------------------------------------------------------------------
#
# Changelog:
#
# Version 0.01 2009-03-20
#   - hilights.pl partly rewritten and renamed it to newsbar.pl
#     (use a bar instead of a buffer)
#     newest version available at:
#     git://github.com/rettub/weechat-plugins.git
#   - based on an idea of Brandon Hartshorn (Sharn) to write highlights into an
#     extra buffer
#     Original script:
#     http: http://github.com/sharn/weechat-scripts/tree/master
#     git:  git://github.com/sharn/weechat-scripts.git

use Data::Dumper;
use Text::Wrap;
use POSIX qw(strftime);
use strict;
use warnings;

my $Version = 0.01;

# constants
#
# script default options
my %SETTINGS = (
    "bar_name"               => "newsbar",
    "show_highlights"        => "on",
    "away_only"              => "off",
    "format_public"          => '%N.%C@%s',
    "show_priv_msg"          => "on",
    "format_private"         => '%N@%s',
    "show_priv_server_msg"   => "on",
    "remove_bar_on_unload"   => "on",
    "memo_tag_color"         => 'yellow',
    "bar_hidden_on_start"    => "1",
    "bar_auto_hide"          => "on",
    "bar_visible_lines"      => "4",
    "bar_seperator"          => "off",
    "bar_title"              => "Highlights",
    "debug"                  => "on",
);

my $SCRIPT      = "newsbar";
my $AUTHOR      = "rettub";
my $LICENCE     = "GPL3";
my $DESCRIPTION = "Listens for news (highlights on all your channels) and writes them into bar 'NewsBar'";
my $COMMAND     = "newsbar";             # new command name
my $ARGS_HELP   = "<always> | <away_only> | <clear [regexp]>"
                 ."| <memo [text]> | <add [--color color] text>"
                 ."| <toggle> | <hide> | <show>"
                 ."| <scroll_home> | <scroll_up> | <scroll_down> | <scroll_end>";
my $CMD_HELP    = <<EO_HELP;
Arguments:

    always:         enable highlights to bar always       (sets 'away_only' = off).
    away_only:      enable highlights to bar if away only (sets 'away_only' = on).
    clear [regexp]: Clear bar '$SETTINGS{bar_name}'. Clear all messages.
                    If a perl regular expression is given, clear matched lines only.
    memo [text]:    Print a memo into bar '$SETTINGS{bar_name}'.
                    If text is not given, an emty line will be printed.

    add [--color color] message:
                    Print a message into bar '$SETTINGS{bar_name}'.
                    Useful to display text printed into the FIFO pipe of WeeChat.
                    Text given before an optional tab will be printed left to the
                    delemeter, all other text will be printed right to the
                    delemeter. If --color weechat-color-name is given text
                    infront of a tab will be colored.
                    The best way to use this command is in a script called by e.g.
                    cron or newsbeuter (maybe using ssh from an other host).
                    Example (commandline):
                    \$ echo -e \\
                        "*/newsbar add --color red [RSS]\\t 3 unread feeds (18 unread articles)" \\
                        > ~/.weechat/weechat_fifo_$$
                    \$ echo "*/newsbar add simple message" > ~/.weechat/weechat_fifo_$$
    toggle,
    hide, show,
    scroll_home,
    scroll_end,
    scroll_up,
    scroll_down:  Simplify the use of eg. '/$SCRIPT scroll_end' instead of '/bar $SCRIPT scroll * ye',
                  and simple use of key bindings.

Config settings:

    away_only:              Collect hihlights only if you're away.
                            default: '$SETTINGS{away_only}'
    show_highlights         Enable/disable handling of public messages. ('on'/'off')
                            default: '$SETTINGS{show_highlights}'
    show_priv_msg           Enable/disable handling of private messages. ('on'/'off')
                            default: '$SETTINGS{show_priv_msg}'
    show_priv_server_msg    Enable/disable handling of private server messages. ('on'/'off')
                            default: '$SETTINGS{show_priv_server_msg}'
    format_public :         Format-string for public highlights.
    format_private:         Format-string for private highlights.

    Format-string:          %n : nick,    %N : colored nick
                            %c : channel, %C : colored channel  (public only)
                            %s : server
                            default public format:  '$SETTINGS{format_public}'
                            default private format: '$SETTINGS{format_private}'

    memo_tag_color          Color of '[memo]' e.g.: 'black,cyan' fg: black, bg: cyan
                            default: '$SETTINGS{memo_tag_color}'
    remove_bar_on_unload    Remove bar when script will be unloaded. 
    bar_auto_hide           Hide bar if empty ('on'/'off')
                            default: '$SETTINGS{bar_auto_hide}'
    bar_hidden_on_start     Start with a hidden bar ('1'/'0')
                            default: '$SETTINGS{bar_hidden_on_start}'
    bar_visible_lines       lines visible if bar is shown
                            default: '$SETTINGS{bar_visible_lines}'
    bar_seperator           Show bar separator line ('on'/'off')
                            default: '$SETTINGS{bar_seperator}'
    bar_title               Title of info bar
                            default: '$SETTINGS{bar_title}'

    debug:                  Show some debug/warning messages on failture. ('on'/'off').
                            default: '$SETTINGS{debug}'

EO_HELP

my $COMPLETITION  =
"always|away_only|clear|memo|add|toggle|hide|show|scroll_down|scroll_up|scroll_home|scroll_end";
my $CALLBACK      = $COMMAND;
my $CALLBACK_DATA = undef;

# global vars
my $Bar;
my $Bar_title;
my $Bar_title_name = 'newsbar_title';
my @Bstr=();
my $Baway="";
my $Bar_hidden=undef;

# helper functions {{{
# FIXME hardcoded max nick-color value to prevent a forever-loop in init_config()
# be ready for 256 colors
{
my $_Ncol    = undef;
my $_MIN_COL = 10;

sub DEBUG {weechat::print('', "***\t" . $_[0]);}

sub _init_max_colors {
    if ( !defined $_Ncol ) {

        # FIXME hardcoded max colors == 15 to prevent a forever-loop
        for ( $_Ncol = 1 ; $_Ncol < 15 ; ) {
            last
              unless weechat::config_get(
                'weechat.color.chat_nick_color' . sprintf( "%02d", $_Ncol ) );
            $_Ncol++;
        }

        $_Ncol--;
        weechat::print( '',
            "$SCRIPT: warning: bad max colors: $_Ncol should be '$_MIN_COL'" )
          if $_Ncol < $_MIN_COL;
    }
}

sub _color_index {
    my $s = shift;
    my ( $h, $v ) = ( 0, 0 );

    map { $h += ord($_) } split( //, $s );

    while ( $h > $_Ncol ) {
        $v = 0;
        map { $v += $_ } split( //, "$h" );
        $h = $v;
    }

    return weechat::config_color(
        weechat::config_get(
            'weechat.color.chat_nick_color' . sprintf( "%02d", $h )
        )
    );
}

sub _color_it { return weechat::color(_color_index($_[0])); }

sub _colored {
    my $a = shift;
    my $np ='[\@+^]';
    my ($b) = ($a =~ /^$np?(.*)/);

    return weechat::color('lightgreen') . '@' . _color_it($b) . $b . weechat::color('default') if $a =~ /^\@/;
    return weechat::color('yellow') . '+' . _color_it($b) . $b . weechat::color('default') if $a =~ /^\+/;
    return _color_it($b) . $a . weechat::color('default')
}

sub _color_str {
    my ($color_name, $str) = @_;
    weechat::color($color_name) . $str  . weechat::color('default');
}

sub _bar_toggle {
    my $cmd = shift;

    if ( $cmd eq 'show' ) {
        $Bar_hidden = 0;
    } elsif ( $cmd eq 'hide' ) {
        $Bar_hidden = 1;
    } elsif ( $cmd eq 'toggle' ) {
        $Bar_hidden = $Bar_hidden ? 0 : 1;
    }

    if ($Bar_hidden) {
        my ( $bar, $bar_title ) = _bar_get();
        weechat::bar_set($bar_title, 'hidden', $Bar_hidden); # XXX bar must be visible before bar_item_update() is called!
        weechat::bar_set($bar, 'hidden', $Bar_hidden); # XXX bar must be visible before bar_item_update() is called!
    } else {
        _bar_show();
    }
}

sub _bar_hide {
    weechat::bar_item_update($Bar_title_name);
    weechat::bar_item_update(weechat::config_get_plugin('bar_name'));

    if (weechat::config_get_plugin('bar_auto_hide') eq 'on' and not @Bstr) {
        $Bar_hidden = 1;
        my ( $bar, $bar_title ) = _bar_get();

        if ($bar and $bar_title) {
            weechat::command('', "/bar hide " . $Bar_title_name);
            weechat::command('', "/bar hide " . weechat::config_get_plugin('bar_name'));
        } else {
            ( $bar, $bar_title ) = _bar_recreate();
        }
    }
}

sub _bar_clear {
    my $arg = shift;

    return unless @Bstr;

    @Bstr = $arg ? grep { not $_->[1] =~ /$arg/} @Bstr : ();

    _bar_hide();
}

sub _bar_date_time {
    my $dt = strftime( weechat::config_string (weechat::config_get('weechat.look.buffer_time_format')), localtime);
    # FIXME user config
    my $tdelim = weechat::color ("yellow") . ":" . weechat::color ("default");
    my $ddelim = weechat::color ("yellow") . "-" . weechat::color ("default");
    $dt =~ s/:/$tdelim/g; 
    $dt =~ s/-/$ddelim/g; 

    return $dt;
}

sub _bar_show {
    my ( $bar, $bar_title ) = _bar_get();

    unless ($bar and $bar_title) {
        ( $bar, $bar_title ) = _bar_recreate();
    }
    if ( $bar and $bar_title ) {
        $Bar_hidden = 0;
        weechat::bar_set($bar_title, 'hidden', '0');    # XXX bars must be visible before
        weechat::bar_set($bar, 'hidden', '0');          #     bar_item_update() is called!
        weechat::bar_item_update($Bar_title_name);
        weechat::bar_item_update( weechat::config_get_plugin('bar_name'));
    } else {
        weechat::print('', "$SCRIPT: ERROR: missing bar, please reload $SCRIPT");
    }
}

sub _bar_print {
    my $str = shift;
    unshift(@Bstr , [_bar_date_time() . " ",  $str]); # insert msg to top

    _bar_show();
}

sub _print_formatted {
    my ( $fmt, $message, @id ) = @_;

    my @f = qw(N C S);
    my $t;
    my $i = 0;
    foreach (@f) {
        if ( $fmt =~ /%($_)/i ) {
            $t = $1 eq $_ ? _colored( $id[$i] ) : $id[$i];
            $fmt =~ s/%$1/$t/;
        }
        $i++;
    }

    _bar_print( $fmt . "\t" . $message); # insert msg to top
}
}
# }}}

# weechat stuff {{{
# colored output of hilighted text to bar
sub highlights_public {
    my ( $bufferp, undef, undef, undef, $ishilight, $nick, $message ) = @_;

    if ( $ishilight == 1
        and weechat::config_get_plugin('show_highlights') eq 'on' )
    {
        if ( weechat::config_get_plugin('away_only') eq 'on' ) {
            return weechat::WEECHAT_RC_OK
              unless weechat::buffer_get_string( $bufferp, "localvar_away" );
        }

        my $btype = weechat::buffer_get_string( $bufferp, "localvar_type" );
        my ( $server, $channel, $fmt ) = (
            weechat::buffer_get_string( $bufferp, "localvar_server" ),
            weechat::buffer_get_string( $bufferp, "localvar_channel" ),
            undef
        );

        if ( $btype eq 'channel' ) {
            $fmt = weechat::config_get_plugin('format_public');
        } elsif ( $btype eq 'private' ) {
            $channel = '';
            $fmt     = weechat::config_get_plugin('format_private');

        } elsif ( $btype eq 'server' ) {
            if ( weechat::config_get_plugin('show_priv_server_msg') eq 'on' ) {
                #TODO check for #channel == $server FIXME needed?
                $fmt     = '%N%c';
                $nick    = $server;
                $channel = weechat::color('magenta') . "[SERVER-MSG]";
            }
        } else { # FIXME
            if ( weechat::config_get_plugin('debug') eq 'on' ) {
                $server  = weechat::buffer_get_string( $bufferp, "localvar_server" ) || 'UNDEF';
                $channel = weechat::buffer_get_string( $bufferp, "localvar_channel" ) || 'UNDEF';
                $btype ||= 'UNDEF';
                weechat::print('', "$SCRIPT: WARNING: highlights_public: nothing done for localvar_type: '$btype'");
                weechat::print('', "$SCRIPT:          * message came form nick:    '$nick'");
                weechat::print('', "$SCRIPT:          * message came form server:  '$server'");
                weechat::print('', "$SCRIPT:          * message came form channel: '$channel'");
            }
        }
        _print_formatted( $fmt, $message, $nick, $channel, $server ) if $fmt;
    }

    return weechat::WEECHAT_RC_OK;
}

# colored output of private messages to bar
# server messages aren't shown in the bar
# format: 'nick[privmsg] | message' (/msg)
sub highlights_private {
    my ( $nick, $message ) = ( $_[1] =~ /(.*?)\t(.*)/ );

    my $fmt = '%N%c';

    _print_formatted( $fmt, $message, $nick, weechat::color('red') . "[privmsg]",
        undef )
      if weechat::config_get_plugin('show_priv_msg') eq "on"
          and $nick ne '--';

    return weechat::WEECHAT_RC_OK;
}

sub newsbar {

    if ( $_[1] eq 'always' ) {
            weechat::config_set_plugin( 'away_only', 'off' );
    } elsif ( $_[1] eq 'away_only' ) {
            weechat::config_set_plugin( 'away_only', 'on' );
    } elsif ( $_[1] eq 'show' or $_[1] eq 'hide' or $_[1] eq 'toggle' ) {
            _bar_toggle( $_[1] );
    } elsif ( $_[1] eq 'scroll_home' ) {
            weechat::command('', "/bar scroll " . weechat::config_get_plugin('bar_name') . " * yb" );
    } elsif ( $_[1] eq 'scroll_end' ) {
            weechat::command('', "/bar scroll " . weechat::config_get_plugin('bar_name') . " * ye" );
    } elsif ( $_[1] eq 'scroll_up' ) {
            weechat::command('', "/bar scroll " .
                weechat::config_get_plugin('bar_name') . " * y-" . weechat::config_get_plugin('bar_visible_lines'));
    } elsif ( $_[1] eq 'scroll_down' ) {
            weechat::command('', "/bar scroll " .
                weechat::config_get_plugin('bar_name') . " * y+" . weechat::config_get_plugin('bar_visible_lines'));
    } else {
        my ( $cmd, $arg ) = ( $_[1] =~ /(.*?)\s+(.*)/ );
        $cmd = $_[1] unless $cmd;
        if ( $cmd eq 'memo' ) {
            _bar_print(
                weechat::color( weechat::config_get_plugin('memo_tag_color') )
                  . "[memo]"
                  . weechat::color('default,default') . "\t"
                  . ( defined $arg ? $arg : '' ) );
        } elsif ( $cmd eq 'clear' ) {
            _bar_clear($arg);
        } elsif ( $cmd eq 'add' ) {
            my ($add_cmd, $value) = ($arg =~ /^(--color)\s+(.*?)(\s+|\$)/);

            if ( defined $add_cmd and $add_cmd eq '--color' ) {
                $arg =~ s/^--color\s+$value//;
                if ( $arg =~ /\t/ ) {
                    my $color_code = weechat::color($value);
                    $color_code = '' if $color_code =~ /F-1/;    # XXX ^Y must be literal ctrl-v,ctrl-Y
                    $arg = $color_code . $arg;
                } else {
                    $arg =~ s/^\s+//;
                    $arg = weechat::color("cyan") . "[INFO]\t" . $arg;
                }
            } else {
                $arg = weechat::color("cyan") . "[INFO]\t" . $arg unless $arg =~ /\t/;
            }

            _bar_print($arg);
        }
    }

    return weechat::WEECHAT_RC_OK;
}

sub init_config {
    _init_max_colors();

    while ( my ( $option, $default_value ) = each(%SETTINGS) ) {
        weechat::config_set_plugin( $option, $default_value )
          if weechat::config_get_plugin($option) eq "";
    }
}

sub highlights_config_changed {
    my $option = shift;
    my $value = shift;

    if ( $value eq 'on' ) {
        $Baway = "IF AWAY";
    } else {
        if( $value ne 'off' ) {
            weechat::print('',  weechat::color('lightred') . "=!=\t" . "$SCRIPT: "
                . _color_str( 'lightred', "ERROR" )
                . ": wrong value: '"
                . _color_str( 'red', $value ) . "' "
                . "for config var 'away_only'. Must be one of '"
                . _color_str('cyan', "on" ) . "', '"
                . _color_str('cyan', "off" ) . "'. I'm using: '"
                . _color_str('cyan', "off" ) . "'."
            );

            # FIXME unhook/rehook needed?
            weechat::unhook( 'highlights_config_changed' );
            weechat::config_set_plugin( 'away_only', 'off' );
            weechat::hook_config( $option, 'highlights_config_changed' );
        }
        $Baway = "ALWAYS";
    }

    return weechat::WEECHAT_RC_OK;
}

sub _bar_exists {
}

sub _bar_get {
    return ( weechat::bar_search( weechat::config_get_plugin('bar_name') ),
        weechat::bar_search($Bar_title_name) );
}

sub _bar_recreate {
    my ( $bar, $bar_title ) = _bar_get();

    weechat::print('', _color_str('yellow', '=!=') . "\t$SCRIPT: recreating missing bars (deleted by user?)");
    weechat::command('', "/bar del " . weechat::config_get_plugin('bar_name')) if $bar;
    weechat::command('', "/bar del " . $Bar_title_name )                       if $bar_title;
    
    init_bar();

    return _bar_get();
}

# Make new bar if needed
sub init_bar {
    my $bar_name = weechat::config_get_plugin('bar_name');

    $Bar_hidden = weechat::config_get_plugin('bar_hidden_on_start')
      unless defined $Bar_hidden;

    unless (defined $Bar) {
        highlights_config_changed(
            "plugins.var.perl." . $SCRIPT . ".on_away",
            weechat::config_get_plugin('away_only')
        );
        weechat::bar_item_new( $bar_name, "build_bar" );
        weechat::bar_new(
            $bar_name,                              $Bar_hidden,
            "100",                                  "root",
            "",                                     "top",
            "vertical",                             "vertical",
            "0",
            weechat::config_get_plugin('bar_visible_lines'),
            "default",                              "default",
            "default",
            weechat::config_get_plugin('bar_seperator'),
            $bar_name
        );
    }
    unless (defined $Bar_title) {
        weechat::bar_item_new( $Bar_title_name, "build_bar_title" );
        weechat::bar_new(
            $Bar_title_name,                        $Bar_hidden,
            "100",                                  "root",
            "",                                     "top",
            "vertical",                             "vertical",
            "0",                                    '1',
            "default",                              "default",
            "default",
            'off',
            $Bar_title_name
        );
    }

    weechat::bar_item_update($Bar_title_name);
    weechat::bar_item_update($bar_name);
}

# FIXME look for FlashCode's ' Force refresh of bars using a bar item when it is destroyed'
# needed for reload too, to be sure to display title before the text bar if e.g.
# text bar was deleted by user
sub unload {
    $Bar = weechat::bar_search( weechat::config_get_plugin('bar_name') );
#    my ( $bar, $bar_title ) = _bar_get();

#    if ($Bar and weechat::config_get_plugin('remove_bar_on_unload') eq 'on') {
        weechat::bar_remove(weechat::bar_search( $Bar_title_name));
        weechat::bar_remove($Bar);
#    }

    return weechat::WEECHAT_RC_OK;
}
# }}}

sub build_bar_title {

    # FIXME user config
    my $title =
        weechat::color(",blue")
      . weechat::config_get_plugin('bar_title')
      . ": [%I] [active: %A | most recent: first]";

    my $i = @Bstr;
    $i ||= 0;

    $title =~ s/%A/$Baway/;
    $title =~ s/%I/$i/;

    return $title;
}

use constant {
    TIME     => 0,
    TIME_CCL => 1,    #    NICK_COLOR_CODE_LEN
    NICK     => 2,
    NICK_CCL => 3,    #    NICK_COLOR_CODE_LEN
    MSG      => 4,
};

# FIXME use columns (width in chars) of bar if possible
sub _terminal_columns { my $c = `tput cols`; chomp $c; return $c; }

# color codes starting with ctrl-Y[FB\*] (gui-color.h)
# FIXME check for color error code: 'F-1'
sub _colorcodes_len {
    my $str = shift;

    # XXX ^Y must be literal ctrl-v,ctrl-Y
    my $COLOR_CODE      = "[FB][0-9a-fA-F]{2,2}";
    my $COLOR_CODE_FGBG = "\*[0-9a-fA-F]{2,2},[0-9a-fA-F]{2,2}";

    return ((scalar (() = $str =~ /$COLOR_CODE/g) * 4) + (scalar (() = $str =~ /$COLOR_CODE_FGBG/g) * 7));
}

sub build_bar {
    my $str = "";
    my @f;
    my $i        = 0;
    my $nlen_max = 0;
    my $tlen_max = 0;    # max lenght of date/time

    # get lengths
    foreach (@Bstr) {
        ($f[$i][NICK], $f[$i][MSG]) = split(/\t/, $_->[1]);
        $f[$i][TIME]                = $_->[0];                          # [date ] time

        $f[$i][TIME_CCL] = _colorcodes_len($f[$i][TIME]);               # length of color codes
        my $tlen_c       = length($f[$i][TIME]) -  $f[$i][TIME_CCL];    # length without color codes
        $tlen_max        = $tlen_c if $tlen_c > $tlen_max;              # new max length

        $f[$i][NICK_CCL] = _colorcodes_len($f[$i][NICK]);
        my $nlen_c       = length($f[$i][NICK]) - $f[$i][NICK_CCL];
        $nlen_max        = $nlen_c if $nlen_c > $nlen_max;
        $i++;
    }

    # FIXME use user config color
    my $delim     = weechat::color ("green") . " | " . weechat::color ("default");

    $Text::Wrap::columns  = _terminal_columns() - ($nlen_max + $tlen_max + 3); # 3 := length of delim without color codes
    $Text::Wrap::unexpand = 0;   # don't turn spaces into tabs

    foreach (@f) {
        if ( length(@$_[MSG]) > $Text::Wrap::columns ) {
            my @a = split( /\n/, wrap( '', '', @$_[MSG] ) );
            $str .= sprintf( "%*s%*s$delim%s\n", $tlen_max, @$_[TIME], $nlen_max  + @$_[NICK_CCL], @$_[NICK], shift @a );
            foreach (@a) {
                $str .= sprintf( "%*s%*s$delim%s\n", $tlen_max, " ", $nlen_max , " ", $_ );
            }
        } else {
            $str .= sprintf( "%*s%*s$delim%s\n", $tlen_max, @$_[TIME], $nlen_max + @$_[NICK_CCL], @$_[NICK], @$_[MSG] );
        }
    }

    return $str;
}

# ------------------------------------------------------------------------------
# here we go...
#
# init script
# XXX If you don't check weechat::register() for succsess, %SETTINGS will be set
# XXX by init_config() into the namespace of other perl scripts.
if ( weechat::register(  $SCRIPT,  $AUTHOR, $Version, $LICENCE, $DESCRIPTION, "unload", "" ) ) {

    weechat::hook_command( $COMMAND,  $DESCRIPTION,  $ARGS_HELP, $CMD_HELP, $COMPLETITION, $CALLBACK );
    weechat::hook_print( "", "", "", 1, "highlights_public" );
    weechat::hook_signal( "weechat_pv",    "highlights_private" );

    init_config();
    init_bar();
    weechat::hook_config( "plugins.var.perl." . $SCRIPT . ".on_away", 'highlights_config_changed' );
}

# vim: ai ts=4 sts=4 et sw=4 foldmethod=marker :
