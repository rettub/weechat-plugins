#
# hilights for weechat version 0.2.7 or later
#
# (perl version by rettub@gmx.net, just to play with weechat and perl)
#
#  Listens for hilights and sends them to a hilight buffer.
#
# -----------------------------------------------------------------------------
#
# This program is free software. It comes without any warranty, to
# the extent permitted by applicable law. You can redistribute it
# and/or modify it under the terms of the Do What The Fuck You Want
# To Public License, Version 2, as published by Sam Hocevar. See
# http://sam.zoy.org/wtfpl/COPYING for more details.
#
#
#             DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#                    Version 2, December 2004
#
# Copyright (C) 2004 Sam Hocevar
#  14 rue de Plaisance, 75014 Paris, France
# Everyone is permitted to copy and distribute verbatim or modified
# copies of this license document, and changing it is allowed as long
# as the name is changed.
#
#            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
#
#  0. You just DO WHAT THE FUCK YOU WANT TO.
#
# -----------------------------------------------------------------------------
#
# Usage:
#
#   Simply load the script, and all hilights in all channels will be sent to a
#   single hilight buffer.
#
#   Simmple commands:
#   /hilights clear        clears the buffer
#   /hilights memo [text]  writes text into the script's buffer
#
# Configuration:
#
#  away_only:       collect hihlights only if away isn't set
#  format_public :  format-string for public hilights
#  format_private:  format-string for private hilights
#                   %n : nick,    %N : colored nick
#                   %c : channel, %C : colored channel
#                   %s : server
#
# -----------------------------------------------------------------------------
#
# Bugs? Would be surprised if not, please tell me!
#
# -----------------------------------------------------------------------------
# TODO Switch back and forth current/'not seen hilighted' buffer
#      Use a local_var to sign buffer with new hilights
#      similar to 'jump_smart'a for unread
# TODO Autoswitch hilight-buffer with buffer of top window if there are splitted
#      windows in the current layout and buffer with new hiligth not visible
# TODO Optional execute an external usr cmd with args:
#        nick, channel, server, message, ... (date/time?)
#      Or write a special scrip for it.
#      Can be uesed for scripts using libnotify, make weechat speaking to you
#      (I use festival for it)
# TODO exclude nicks, channels, servers, ... by eg. user defined whitelists
#      and/or blacklists
# TODO config option to en/disable the logger for hilight buffer
#
# -----------------------------------------------------------------------------
#
# Changelog:
#
# Version 0.04, 15 Mar, 2009
#   - renamed cmd arg 'on_away' to 'away_only'

# Version 0.03, 15 Mar, 2009
#   - Don't clash with Sharn's python script anymore
#     renamed hilightbuffer.pl -> hilights.pl
#     renamed cmd /hilightbuffer to /hilights
#     renamed default buffername to "hilights"
#     XXX If you don't use hilightbuffer.pl anymore,
#         please remove old config vars manually
#           plugins.var.perl.hilightbuffer.*
#   - FIX: use of buffer localvar_type to check for private/public hihilghts
#   - FIX: check return val of weechat::register()
#   - added config option to listen if away only
#     new config option: 'away_only'
#     new cmd args: always, away_only
#     Check if value for 'away_only' is one of 'on,'off' when changed
#     and on startup. Fall back to 'off'.
#   - config option 'format_private' for user formatted output
#   - color nick prefixes @,+,^ with extra colors
#
# Version 0.02, 11 Mar, 2009
#   - FIX: ignore server 'private' messages
#   - config option 'format_public' for user formatted output
#   - new script commands: clear, memo
#   - add hooks first, then initialize
#   - get max number of nick-colors from weechat config
#   - notification_* config vars removed
#   - get color names for nicks)from current weechat config
#   - removed unneeded vars
#
# Version 0.1, 01 Mar, 2009
#   - added some color output, removed external notify
#   - ported original python version of Brandon Hartshorn (Sharn) into perl
#     Original script:
#     http: http://github.com/sharn/weechat-scripts/tree/master
#     git:  git://github.com/sharn/weechat-scripts.git

use strict;
use warnings;

my $Version = 0.04;

# constants
#
# script default options
my %SETTINGS = (
    "buffer_name"     => "hilights",
    "show_hilights"  => "on",
    "away_only"      => "off",
    "format_public"  => '%N.%C@%s',
    "show_priv_msg"  => "on",
    "format_private" => '%N@%s'
);

my $SCRIPT      = "hilights";
my $AUTHOR      = "rettub";
my $LICENCE     = "WTFPL";
my $DESCRIPTION = "Listens for hilights on all your channels and writes them to common buffer '$SETTINGS{buffer_name}'";
my $COMMAND     = "hilights";             # new command name
my $ARGS_HELP   = "<always> | <away_only> | <clear> | <memo [text]>";
my $CMD_HELP    = <<EO_HELP;
Arguments:

    always:       enable hilights to buffer always       (sets 'away_only' = off).
    away_only:    enable hilights to buffer if away only (sets 'away_only' = on).
    clear      :  Clear buffer '$SETTINGS{buffer_name}'.
    memo [text]:  Print a memo into buffer '$SETTINGS{buffer_name}'.
                  If text is not given, an emty line will be printed.

Config settings:

    away_only:       Collect hihlights only if you're away.
                     default: '$SETTINGS{away_only}'
    format_public :  Format-string for public hilights.
    format_private:  Format-string for private hilights.
                     %n : nick,    %N : colored nick
                     %c : channel, %C : colored channel  (public only)
                     %s : server
                     default public format:  '$SETTINGS{format_public}'
                     default private format: '$SETTINGS{format_private}'

 *** The buffer '[perl] $SETTINGS{buffer_name}' can't be closed, it will be recreated immediatly.
 *** To get rid of the buffer, just unload $SCRIPT
EO_HELP

my $COMPLETITION  = "always|away_only|clear|memo";
my $CALLBACK      = $COMMAND;
my $CALLBACK_DATA = undef;

# global vars
my $Buffer;

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

    weechat::print( $Buffer, $fmt . "\t" . $message );
}
}
# }}}

# weechat stuff {{{
# colored output of hilighted text to hilight buffer
sub hilights_public {
    my ( $bufferp, undef, undef, undef, $ishilight, $nick, $message ) = @_;

    if ( $ishilight == 1
        and weechat::config_get_plugin('show_hilights') eq 'on' )
    {
        if ( weechat::config_get_plugin('away_only') eq 'on' ) {
            return weechat::WEECHAT_RC_OK
              unless weechat::buffer_get_string( $bufferp, "localvar_away" );
        }

        my $btype = weechat::buffer_get_string( $bufferp, "localvar_type" );
        my ( $server, $channel, $fmt ) = ( '', '', undef );

        if ( $btype eq 'channel' ) {
            $server  = weechat::buffer_get_string( $bufferp, "localvar_server" );
            $channel = weechat::buffer_get_string( $bufferp, "localvar_channel" );
            $fmt     = weechat::config_get_plugin('format_public');
        } elsif ( $btype eq 'private' ) {
            $server = weechat::buffer_get_string( $bufferp, "localvar_server" );
            $fmt = weechat::config_get_plugin('format_private');
        } else { # FIXME
            weechat::print('', "ERROR hilights_public nothing done for localvar_type: '$btype'");
        }
        _print_formatted( $fmt, $message, $nick, $channel, $server ) if $fmt;
    }

    return weechat::WEECHAT_RC_OK;
}

# colored output of private messages to hilight buffer
# server messages aren't shown in the hilight buffer
# format: 'nick[privmsg] | message' (/msg)
sub hilights_private {
    my ( $nick, $message ) = ( $_[1] =~ /(.*?)\t(.*)/ );

    my $fmt = '%N%c';

    _print_formatted( $fmt, $message, $nick, weechat::color('red') . "[privmsg]",
        undef )
      if weechat::config_get_plugin('show_priv_msg') eq "on"
          and $nick ne '--';

    return weechat::WEECHAT_RC_OK;
}

sub hilights {

    if ( $_[1] eq 'clear' ) {
        weechat::buffer_clear($Buffer);
    } elsif ( $_[1] eq 'always' ) {
            weechat::config_set_plugin( 'away_only', 'off' );
    } elsif ( $_[1] eq 'away_only' ) {
            weechat::config_set_plugin( 'away_only', 'on' );
    } else {
        my ( $cmd, $arg ) = ( $_[1] =~ /(.*?)\s+(.*)/ );
        $cmd = $_[1] unless $cmd;
        if ( $cmd eq 'memo' ) {
            weechat::print( $Buffer,
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

sub hilights_config_changed {
    my $option = shift;
    my $value = shift;

    if ( $value eq 'on' ) {
        weechat::buffer_set ($Buffer, "title", "$SCRIPT: [active: IF AWAY]");
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
            weechat::unhook( 'hilights_config_changed' );
            weechat::config_set_plugin( 'away_only', 'off' );
            weechat::hook_config( $option, 'hilights_config_changed' );
        }
        weechat::buffer_set ($Buffer, "title", "$SCRIPT: [active: ALWAYS]");
    }

    return weechat::WEECHAT_RC_OK;
}

# Make new buffer for hilights if needed
sub init_buffer {
    my $buffer_out = weechat::config_get_plugin('buffer_name');
    my $bn = weechat::buffer_search( "perl", $buffer_out );

    if ($bn) {
        $Buffer = $bn;
    } else {
        weechat::buffer_new( $buffer_out, "", "" );
        $Buffer = weechat::buffer_search( "perl", $buffer_out );
    }

    my $value = weechat::config_get_plugin('away_only');
    if ( $value eq 'on' ) {
        weechat::buffer_set( $Buffer, "title", "$SCRIPT: [active: IF AWAY]" );
    } else {
        if ( $value ne 'off' ) {
            weechat::config_set_plugin( 'away_only', 'off' );
        }
        weechat::buffer_set( $Buffer, "title", "$SCRIPT: [active: ALWAYS]" );
    }
}

# don't crash weechat if hilight buffer was closed
# FIXME make a cmd like stop/start cause buffer for hilights can't be deactivated
sub hilights_buffer_closed {
    init_buffer() if $_[1] eq $Buffer;

    return weechat::WEECHAT_RC_OK;
}
# }}}

# ------------------------------------------------------------------------------
# here we go...
#
# init script
# XXX If you don't check weechat::register() for succsess, %SETTINGS will be set
# XXX by init_config() into the namespace of other perl scripts.
if ( weechat::register(  $SCRIPT,  $AUTHOR, $Version, $LICENCE, $DESCRIPTION, "", "" ) ) {

    weechat::hook_command( $COMMAND,  $DESCRIPTION,  $ARGS_HELP, $CMD_HELP, $COMPLETITION, $CALLBACK );
    weechat::hook_print( "", "", "", 1, "hilights_public" );
    weechat::hook_signal( "weechat_pv",    "hilights_private" );
    weechat::hook_signal( "buffer_closed", "hilights_buffer_closed" );

    init_config();
    init_buffer();
    weechat::hook_config( "plugins.var.perl.hilights.on_away", 'hilights_config_changed' );
}

# vim: ai ts=4 sts=4 et sw=4 foldmethod=marker :
