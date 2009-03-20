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
#  Simmple commands:
#  /newsbar always       enable highlights to bar always.
#  /newsbar away_only    enable highlights to bar if away only
#  /newsbar clear        clears the bar
#  /newsbar memo [text]  writes text into the script's bar
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
#  remove_bar_on_unload    Remove bar when script will be unloaded. 
#  bar_hidden_on_start     Start with a hidden bar.
#  bar_visible_lines       lines visible if bar is shown.
#
#  debug:                  Show some debug/warning messages on failture
#
# -----------------------------------------------------------------------------
#
# Bugs? Would be surprised if not, please tell me!
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
    "bar_hidden_on_start"    => "1",
    "bar_visible_lines"      => "4",
    "debug"                  => "on",
);

my $SCRIPT      = "newsbar";
my $AUTHOR      = "rettub";
my $LICENCE     = "GPL3";
my $DESCRIPTION = "Listens for news (highlights on all your channels) and writes them into bar 'NewsBar'";
my $COMMAND     = "newsbar";             # new command name
my $ARGS_HELP   = "<always> | <away_only> | <clear> | <memo [text]> | <toggle> | <hide> | <show> | <scroll_home> | <scroll_up> | <scroll_down> | <scroll_end>";
my $CMD_HELP    = <<EO_HELP;
Arguments:

    always:       enable highlights to bar always       (sets 'away_only' = off).
    away_only:    enable highlights to bar if away only (sets 'away_only' = on).
    clear      :  Clear bar '$SETTINGS{bar_name}'.
    memo [text]:  Print a memo into bar '$SETTINGS{bar_name}'.
                  If text is not given, an emty line will be printed.
    toggle,
    hide, show,
    scroll_home,
    scroll_end,
    scroll_up,
    scroll_down:  Simplify the use of eg. '/$SCRIPT scroll_down' instead of '/bar $SCRIPT scroll * yb',
                  and simple use of key bindings.

Config settings:

    away_only:              Collect hihlights only if you're away.
                            default: '$SETTINGS{away_only}'
    show_highlights         Enable/disable handling of public messages. ('on'/'off')
                            default: :  '$SETTINGS{show_highlights}'
    show_priv_msg           Enable/disable handling of private messages. ('on'/'off')
                            default: :  '$SETTINGS{show_priv_msg}'
    show_priv_server_msg    Enable/disable handling of private server messages. ('on'/'off')
                            default: :  '$SETTINGS{show_priv_server_msg}'
    format_public :         Format-string for public highlights.
    format_private:         Format-string for private highlights.

    Format-string:          %n : nick,    %N : colored nick
                            %c : channel, %C : colored channel  (public only)
                            %s : server
                            default public format:  '$SETTINGS{format_public}'
                            default private format: '$SETTINGS{format_private}'

    remove_bar_on_unload    Remove bar when script will be unloaded. 
    bar_hidden_on_start     Start with a hidden bar ('1'/'0')
                            default: :  '$SETTINGS{bar_hidden_on_start}'
    bar_visible_lines       lines visible if bar is shown
                            default: :  '$SETTINGS{bar_visible_lines}'

    debug:                  Show some debug/warning messages on failture. ('on'/'off').
                            default: '$SETTINGS{debug}'

EO_HELP

my $COMPLETITION  =
"always|away_only|clear|memo|toggle|hide|show|scroll_down|scroll_up|scroll_home|scroll_end";
my $CALLBACK      = $COMMAND;
my $CALLBACK_DATA = undef;

# global vars
my $Bar;
my @Bstr=();
my $Baway="";

# helper functions {{{
# FIXME hardcoded max nick-color value to prevent a forever-loop in init_config()
# be ready for 256 colors
{
my $_Ncol    = undef;
my $_MIN_COL = 10;

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

sub _bar_clear {
    @Bstr = ();
    weechat::bar_item_update( weechat::config_get_plugin('bar_name'));
}

sub _date_time {
    my $dt = strftime( weechat::config_string (weechat::config_get('weechat.look.buffer_time_format')), localtime);
    # FIXME user config
    my $tdelim = weechat::color ("yellow") . ":" . weechat::color ("default");
    my $ddelim = weechat::color ("yellow") . "-" . weechat::color ("default");
    $dt =~ s/:/$tdelim/g; 
    $dt =~ s/-/$ddelim/g; 

    return $dt;
}

sub _print_bar {
    my $str = shift;
    unshift(@Bstr , [_date_time() . " ",  $str]); # insert msg to top
#    build_bar();
    my $bar = weechat::bar_search( weechat::config_get_plugin('bar_name'));
    if ( $bar) {
        weechat::bar_set($bar, 'hidden', '0'); # XXX bar must be visible before bar_item_update() is called!
        weechat::bar_item_update( weechat::config_get_plugin('bar_name'));
    } else {
        DEBUG("_print_formatted(): ERROR, no bar");
    }
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

    _print_bar( $fmt . "\t" . $message); # insert msg to top
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

    if ( $_[1] eq 'clear' ) {
        _bar_clear();
    } elsif ( $_[1] eq 'always' ) {
            weechat::config_set_plugin( 'away_only', 'off' );
    } elsif ( $_[1] eq 'away_only' ) {
            weechat::config_set_plugin( 'away_only', 'on' );
    } elsif ( $_[1] eq 'show' or $_[1] eq 'hide' or $_[1] eq 'toggle' ) {
            weechat::command('', "/bar $_[1] " . weechat::config_get_plugin('bar_name') );
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
            _print_bar( 
                weechat::color('yellow') . "[memo]" . "\t" . (defined $arg ? $arg : ''));
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

# Make new bar if needed
sub init_bar {
    my $bbar = weechat::config_get_plugin('bar_name');

    unless (defined $Bar) {
        highlights_config_changed(
            "plugins.var.perl." . $SCRIPT . ".on_away",
            weechat::config_get_plugin('away_only')
        );
        weechat::bar_item_new(  weechat::config_get_plugin('bar_name'), "build_bar" );
        weechat::bar_new(
            weechat::config_get_plugin('bar_name'),
            weechat::config_get_plugin('bar_hidden_on_start'),
            "0",                                    "root",
            "",                                     "top",
            "vertical",                             "vertical",
            "0",
            weechat::config_get_plugin('bar_visible_lines'),
            "default",                              "default",
            "default",                              "on",
            weechat::config_get_plugin('bar_name')
        );
    }
    weechat::bar_item_update( weechat::config_get_plugin('bar_name'));
}

sub unload {
    $Bar = weechat::bar_search( weechat::config_get_plugin('bar_name') );

    if ($Bar and weechat::config_get_plugin('remove_bar_on_unload') eq 'on') {
        weechat::bar_remove($Bar);
    }

    return weechat::WEECHAT_RC_OK;
}
# }}}

sub build_bar_title {
    my $i = shift;

    # FIXME user config
    my $title = weechat::color (",blue") .  "NewsBar: [%I] [active: %A | most recent: first]";

    $i ||= 0;

    $title =~ s/%A/$Baway/;
    $title =~ s/%I/$i/;

    return $title;
}

sub build_bar {
    my $str ="";
    my @f;
    my $i=0;
    my $len=0;
    my $plen=0;
    my $plen_c=0;

    foreach (@Bstr) {
        ($f[$i][0], $f[$i][1])=split(/\t/, $_->[1]);

        $f[$i][4] = $_->[0];
        $f[$i][5]= (($f[$i][4] =~ tr///) * 4); # XXX ^Y must be literal ctrl-v,ctrl-Y
        $plen_c = length($f[$i][4]) -  $f[$i][5];
        $plen = $plen_c > $plen ? $plen_c : $plen;

        my $l1 = length($f[$i][0]) ;
        $f[$i][2]= (($f[$i][0] =~ tr///) * 4); # XXX ^Y must be literal ctrl-v,ctrl-Y
        my $l = length($f[$i][0]) - $f[$i][2];
        $len = $l > $len ? $l : $len;
        $i++;
    }

    # FIXME use user config color
    my $delim = weechat::color ("green") . "|" . weechat::color ("default");

    # FIXME use columns (width in chars) of bar if possible
    $Text::Wrap::columns = `tput cols` - $len - 3;
    foreach (@f) {
        if ( length(@$_[1]) > $Text::Wrap::columns ) {
            my @a = split( /\n/, wrap( '', '', @$_[1] ) );
            $str .= sprintf( "%*s%*s %s %s\n", $plen + @$_[5], @$_[4], $len  + @$_[2], @$_[0], $delim, shift @a );
            foreach (@a) {
                $str .= sprintf( "%*s%*s %s %s\n", $plen, " ", $len, " ", $delim, $_ );
            }
        } else {
            $str .= sprintf( "%*s%*s %s %s\n", $plen + @$_[5],@$_[4], $len + @$_[2], @$_[0], $delim, @$_[1] );
        }
    }

    $str = build_bar_title($i) . "\n" . $str;

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
