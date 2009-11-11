# -----------------------------------------------------------------------------
#
# query_blocker.pl - Simple blocker for private messages (i.e. spam).
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
#
# Simple IRC query blocker.
# - requires WeeChat 0.3.0 or newer
# - suggests perl script newsbar
#
# Got inspiration from (xchat script):
# GodOfGTA's Query-Blocker (eng) 1.2.3
#   http://home.arcor.de/godofgta/xchat/queryblocker-eng.pl
#
#
# Newest version available at:
#   git://github.com/rettub/weechat-plugins.git
#
# -----------------------------------------------------------------------------
# History:
#
# 2009-11-03, rettub:
#     version 0.1: initial release
#
# FIXME
#   - add 'mynick' to list - needed?
#
# TODO
#   - don't show message of a blocked query, only show nick and server (by option).
#   - make Auto-Messages configurable

use Data::Dumper;
use warnings;
use strict;

my $SCRIPT      = 'query_blocker';
my $AUTHOR      = 'rettub <rettub@gmx.net>';
my $VERSION     = '0.1';
my $LICENSE     = 'GPL3';
my $DESCRIPTION = 'Simple blocker for private message (i.e. spam)';
my $COMMAND     = "query_blocker";             # new command name
my $ARGS_HELP   = "<on> | <off> | <status> | <list [last]> | <add [nick_1 [... [nick_n]]]> | <del nick_1 [... [nick_n]]> | <reload> | <blocked [clear]>";
my $CMD_HELP    = <<EO_HELP;

Arguments:

    on/off:             toggle blocking of queries.
    status:             show blocking status.
    list [last]:        show whitelist, use last to show the nick blocked last.
    add/del [nicks]:    add/delete nick(s) to/from whitelist. (if no nick is given, 'add' will use the last blocked one).
                        ('nicks' is a list of nicks seperated by spaces).
    reload:             reload whitelist (useful if you changed the file-location i.e. to use a common file).
    blocked [clear]:    list blocked nicks. If arg 'clear' is given all blocked nicks will be removed.

Script Options:
    whitelist:          path/file-name to store/read nicks not to be blocked.
    block_queries:      'on', 'off' to enable or disable $COMMAND.

By default all private messages (/query, /msg) from nicks not in the whitelist will be blocked.
 - to allow all private message, $SCRIPT can be disabled, type '/$COMMAND off'.
 - to allow private messages from certain nicks, put them into the whitelist, type '/$COMMAND add nick'.
 - to remove a nick from the whitelist, type '/$COMMAND del nick'.

If a not allowed (blocked) nick sends you a private message, you will see a notice about nick, server and the message, but no buffer will be ceated. Then the nick gets a 'blocked' state, which will prevent you from seeing his queries again till you restart WeeChat or you put the nick into the whitelist.
(If you use the script 'newsbar', all notices about blocked private messages will go there, otherwise they will appear in your server buffer).

If a not allowed (blocked) nick will send you a private message, he will be informed about blocking by an auto responce message. So he can ask you in the public channel to allow his private messages.

NOTE: If you load $SCRIPT the first time, blocking of private messages is disabled, you have to enable blocking, type '/$COMMAND on'.
EO_HELP

my $COMPLETITION  = "on|off|status|list|add|del|reload|blocked";
my $CALLBACK      = $COMMAND;
my $CALLBACK_DATA = undef;

# script options
my %SETTINGS = (
    "block_queries" => "off",
    "whitelist" =>  "qb-whitelist.txt",
);

# FIXME store server too?
my $Last_query_nick = undef;
my $deny_message = "Auto-Message: Right now I ignore all queries - perhaps not all :)";

sub DEBUG {weechat::print('', "***\t" . $_[0]);}

# {{{ helpers
# 
# irc_nick_find_color: find a color for a nick (according to nick letters)
# (ported to perl from WeeChats source)
sub irc_nick_find_color
{
    my $color = 0;
    foreach my $c (split(//, $_[0]))
    {
        $color += ord($c);
    }
    $color = ($color %
             weechat::config_integer (weechat::config_get ("weechat.look.color_nicks_number")));

    my $color_name = sprintf("chat_nick_color%02d", $color + 1);
    
    return weechat::color ($color_name);
}
# }}}

my %Blocked = ();
my %Allowed = ();

sub nick_allowed { return exists $Allowed{ lc $_[0] }; }

sub whitelist_read {
    my $whitelist = weechat::config_get_plugin( "whitelist" );
    return unless -e $whitelist;
    open (WL, "<", $whitelist) || DEBUG("$whitelist: $!");
	while (<WL>) {
		chomp;
		$Allowed{$_} = 1  if length $_;
	}
	close WL;
}

sub whitelist_save {
    my $whitelist = weechat::config_get_plugin( "whitelist" );
    open (WL, ">", $whitelist) || DEBUG("write whitelist: $!");
    print WL "$_\n" foreach ( sort { "\L$a" cmp "\L$b" } keys %Allowed );
    close WL;
}

sub info2newsbar {
    my ( $server, $nick, $message ) = @_;

    weechat::command( '',
            "/newsbar  add --color lightred [QUERY-WARN]\t"
          . irc_nick_find_color($nick)
          . $nick
          . weechat::color('reset') . '@'
          . irc_nick_find_color($server)
          . $server
          . weechat::color('reset')
          . weechat::color('bold')
          . " tries to start a query: "
          . weechat::color('reset')
          . $message );
    weechat::command( '',
            "/newsbar  add --color lightred [QUERY-WARN]\t"
          . "To allow the query, type: "
          . weechat::color('bold')
          . "/$COMMAND add " . weechat::color('reset') . $nick );
}

# FIXME server needed?
sub info_as_notice {
    my ( $server, $my_nick, $nick, $message ) = @_;

    weechat::command( '', "/notice -server $server $my_nick $nick Tries to start aquery: $message" );
    weechat::command( '', "/notice -server $server $my_nick $nick To allow the query type: /$COMMAND add $nick" );
}

# FIXME do not send a 'blocked' message to query_nick if done already
sub modifier_irc_in_privmsg {
    my ( $data, $signal, $server, $arg ) = @_;

    my $my_nick = weechat::info_get( 'irc_nick', $server );

    #  $sender: :rettub!n=amar@dtmd-4d0bf1cd.pool.mediaWays.net PRIVMSG jhd :msg oooo
    if ( $arg =~ m/:(.+?)\!.+? PRIVMSG $my_nick :(\w.*)/ ) {
        my $query_nick = $1;
        my $query_msg  = $2;

        # if nick is allowed to send queries, let WeeChat handle the query
        return $arg if nick_allowed($query_nick);

        $Last_query_nick = $query_nick;

        unless ( exists $Blocked{$query_nick} ) {
            my $info_list = weechat::infolist_get( "perl_script", "name", "newsbar" );
            weechat::infolist_next($info_list);
            my $ps_name = weechat::infolist_string( $info_list, "name" );

            if ( $ps_name eq 'newsbar' ) {
                info2newsbar( $server, $query_nick, $query_msg );
            } else {
                info_as_notice( $server, $my_nick, $query_nick, $query_msg );
            }

            # auto responce msg to query_nick
            weechat::command( '', "/msg -server $server $query_nick $deny_message " );
            $Blocked{$query_nick} = 0;
        }
            $Blocked{$query_nick}++;
    } else {
        return $arg;
    }

    # return empty string - don't create a new buffer
    return '';
}

sub _add {
    my $arg = shift;

    if ( defined $arg ) {
        foreach ( split( / +/, $arg ) ) {
            $Last_query_nick = undef if ( defined $Last_query_nick and $_ eq $Last_query_nick );
            $Allowed{$_} = 1;
            delete $Blocked{$_};
            weechat::print( '', "Allow queries for: '" . irc_nick_find_color($_) . $_ . weechat::color('reset') . "'");
        }
        whitelist_save();
    } elsif ( defined $Last_query_nick and not exists $Allowed{$Last_query_nick} ) {
        $Allowed{$Last_query_nick} = 1;
        delete $Blocked{$Last_query_nick};
        weechat::print( '', "Allow queries for: '" . irc_nick_find_color($Last_query_nick) . $Last_query_nick . weechat::color('reset') . "'");
        $Last_query_nick = undef;
        whitelist_save();
        # FIXME: open query window
    } else {
        weechat::print( '', "There is no nick to be added to the whitelist");
    }
}

{
my $Block_query    = undef;
my $Block_msg      = undef;
my $Block_modifier = undef;

sub qb_hook {
    $Block_query = weechat::hook_command_run( '/query *', 'qb_query', "" );
    $Block_msg   = weechat::hook_command_run( '/msg *',   'qb_msg',   "" );
    $Block_modifier = weechat::hook_modifier( "irc_in_privmsg", "modifier_irc_in_privmsg", "" );
}

sub qb_unhook {
    weechat::unhook( $Block_query );
    weechat::unhook( $Block_msg );
    weechat::unhook( $Block_modifier );
    $Block_query    = undef;
    $Block_msg      = undef;
    $Block_modifier = undef;
}
}

sub query_blocker {
    my ( $data, $buffer, $args ) = ( $_[0], $_[1], $_[2] );

    if ( $args eq 'on' ) {
        unless (weechat::config_get_plugin('block_queries') eq "on") {
            weechat::config_set_plugin( 'block_queries', 'on' );
            qb_hook();
            weechat::print( '', "$COMMAND: private messages will be blocked");
        } else {
            weechat::print( '', "$COMMAND: private messages blocked already");
        }
    } elsif ( $args eq 'off' ) {
        unless (weechat::config_get_plugin('block_queries') eq "off") {
            weechat::config_set_plugin( 'block_queries', 'off' );
            qb_unhook();
            weechat::print( '', "$COMMAND: disabled");
        } else {
            weechat::print( '', "$COMMAND: was disabled already");
        }
    } elsif ( $args eq 'status' ) {
        if ( weechat::config_get_plugin( 'block_queries') eq 'on' ) {
            weechat::print( '', "$COMMAND: private messages will be blocked");
        } else {
            weechat::print( '', "$COMMAND: disabled");
        }
    } elsif ( $args eq 'reload' ) {
        whitelist_read();
    } else {
        my ( $cmd, $arg ) = ( $args =~ /(.*?)\s+(.*)/ );
        $cmd = $args unless $cmd;
        if ( $cmd eq 'list' ) {
            if ( defined $arg and $arg eq 'last' ) {
                if (defined $Last_query_nick) {
                    weechat::print( '', "Last blocked nick: '" . irc_nick_find_color($Last_query_nick) . $Last_query_nick . weechat::color('reset') . "'");
                } else {
                    weechat::print( '', "No blocked nicks");
                }
            } else {
                my $n = keys %Allowed;
                weechat::print( '', "Allowed nicks for queries ($n):" );
                foreach ( sort { "\L$a" cmp "\L$b" } keys %Allowed ) {
                    weechat::print( '', "   " . irc_nick_find_color($_) . $_ );
                }
            }
        } elsif ( $cmd eq 'blocked' ) {
            if ( keys %Blocked ) {
                if ( defined $arg and $arg eq 'clear' ) {
                    foreach ( sort { "\L$a" cmp "\L$b" } keys %Blocked ) {
                        weechat::print( '', "Removing blocked state from" . irc_nick_find_color($_) . $_ );
                        delete $Blocked{$_};
                    }
                } else {
                    weechat::print( '', "Queries of this nicks have been blocked:" );
                    foreach ( sort { "\L$a" cmp "\L$b" } keys %Blocked ) {
                        weechat::print( '', "   " . irc_nick_find_color($_) . $_ . weechat::color('reset') . " (#$Blocked{$_})");
                    }
                }
            } else {
                weechat::print( '', "No nicks have been blocked" );
            }
        } elsif ( $cmd eq 'add' ) {
            _add($arg);
        }elsif ( $cmd eq 'del' and defined $arg ) {
            foreach ( split( / +/, $arg ) ) {
                if (exists $Allowed{$_} ) {
                    delete $Allowed{$_};
                    weechat::print( '', "Nick removed from whitelist: '" . irc_nick_find_color($_) . $_ . weechat::color('reset') . "'");
                } else {
                    weechat::print( '', "Can't remove nick, not in whitelist: '" . irc_nick_find_color($_) . $_ . weechat::color('reset') . "'");
                }
            }
            whitelist_save();
        }
    }
    return weechat::WEECHAT_RC_OK;
}

sub _get_nick {
    my ($l) = shift;
    $l =~ s/\/(query|msg) +//;

    if ($l =~ /-server/ ) {
        $l =~ s/-server \w+ //;
    }
    
    $l =~ s/ .*$//;

    return $l;
}

sub qb_query {
    my $n = _get_nick($_[2]);
    _add($n) unless nick_allowed($n);

    return weechat::WEECHAT_RC_OK;
}

sub qb_msg {
#    my $nick = ($_[2] =~ /:(.+?)\!.+? PRIVMSG $my_nick :(\w.*)/ 
    my $n = _get_nick($_[2]);
    #_add($n) unless nick_allowed($n) or $_[2] =~ /$deny_message/;
    _add($n) unless nick_allowed($n) or $_[2] =~ /Auto-Message/;

    return weechat::WEECHAT_RC_OK;
}

# -----------------------------------------------------------------------------
#
if ( weechat::register( $SCRIPT, $AUTHOR, $VERSION, $LICENSE, $DESCRIPTION, "", "" ) ) {
    weechat::hook_command( $COMMAND, $DESCRIPTION, $ARGS_HELP, $CMD_HELP, $COMPLETITION, $CALLBACK, "" );

    # FIXME [bug #27936]
    if ( weechat::config_get_plugin("whitelist") eq '' ) {
        my $wd = weechat::info_get( "weechat_dir", "" );
        $wd =~ s/\/$//;
        weechat::config_set_plugin( "whitelist", $wd . "/" . $SETTINGS{"whitelist"} );
    }
    while ( my ( $option, $default_value ) = each(%SETTINGS) ) {
        weechat::config_set_plugin( $option, $default_value )
          if weechat::config_get_plugin($option) eq "";
    }
    whitelist_read();
    weechat::print( '', "$COMMAND: loaded whitelist '" . weechat::config_get_plugin( "whitelist" ) . "'");

    if (weechat::config_get_plugin('block_queries') eq "on") {
        qb_hook();
        weechat::print( '', "$COMMAND: private messages will be blocked");
    } else {
        weechat::print( '', "$COMMAND: disabled");
    }
}

# vim: ai ts=4 sts=4 et sw=4 tw=0 foldmethod=marker :