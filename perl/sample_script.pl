# -----------------------------------------------------------------------------
# Copyright (c) 2010 by rettub <rettub@gmx.net>
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
# Changelog:
#
BEGIN {

    sub changelog {
        my $print = shift;
        my $clog = <<END;
# Version 0.01 2010-01-21
#
#   * Initial Version
END
        my @cl = split( "\$", $clog );
        if (not defined $print ) {
        weechat::print( "", "" );
        weechat::print( "", "\tsample_script: Changelog since last version: " );
        weechat::print( "", "\t-------------------------------------------- " );
    } else {
        print( "\n" );
        print( "sample_script: Changelog since last version: \n" );
        print( "-------------------------------------------- \n" );
    }
        foreach my $i (@cl) {

            # FIXME
            #$i =~ s/#//;           # doesn't work
            # $i =~ s/ignore/XXX/;  # works
            if (not defined $print ) {
                weechat::print( "", "\t$i" );
            } else {
                print( $i );
            }
        }
    }
}

# -----------------------------------------------------------------------------

use 5.006;

#use Carp;	    # don't use die in modules
#use Carp::Clan;    # or better use this

use strict;
use warnings;

my $Version = "0.01";

sub version {
    $Version;
}

my $AUTHOR  = "rettub";
my $LICENCE = "GPL3";
my $SCRIPT  = 'sample_script';

my %SETTINGS = ('option' =>'on');

my $COMMAND       = "sample_cmd";
my $CALLBACK      = $COMMAND;
my $COMPLETITION  = "help || changelog";
my $CALLBACK_DATA = "";
my $DESCRIPTION   = "simple sample script for weechat, can be run on shell or in weechat";
my $USAGE         = <<EOF;
    \$ perl $SCRIPT [help] | [changelog]
EOF

my $ARGS = "[help] | [changelog]";

my $CMD_HELP = <<EOF;

    This $SCRIPT can print help and changelog either started from perl or as plugin script within weechat

    args:
      help:      print this help
      changelog: show changelog since last version

    Options:
      option:    here could be some help for options with values e.g <c>on</c>, <c>off</c> (default: 'on')

    Command is executed like: /$SCRIPT changelog
EOF

my $DEBUG = 1;
my $_debug;
my $_print;

sub wc_debug {
    weechat::print( '', "***\t" . $SCRIPT . ": $_[0]" ) if $DEBUG;
}

sub perl_debug {
    print( $SCRIPT . ": $_[0]\n" ) if $DEBUG;
}

sub wc_print {
    weechat::print( '', $_[0] );
}

sub perl_print {
    print( "$_[0]\n" );
}

sub help {
    return $CMD_HELP;
}

sub sample_cmd {
    my $arg = $_[2];

    if ( $arg eq 'help' ) {
        weechat::print( '', $DESCRIPTION );
        weechat::print( '', $CMD_HELP );
    } elsif ( $arg eq 'changelog' ) {
        changelog();
    } else {

        $_print->( "no args secified for sample_cmd! \n\n");
        $_print->( "\u$DESCRIPTION\n\n$CMD_HELP");
    }
    return eval "weechat::WEECHAT_RC_OK;";
}

sub init_weechat_script {
    if ( weechat::register( $SCRIPT, $AUTHOR, $Version, $LICENCE, $DESCRIPTION, "", "" ) ) {

        # Hooks
        weechat::hook_command( $COMMAND, $DESCRIPTION, $ARGS, $CMD_HELP, $COMPLETITION, $CALLBACK, $CALLBACK_DATA );

        #    init_config();
        $_debug = sub { wc_debug( $_[0] ); };
        $_print = sub { wc_print( $_[0] ); };
    }
}

sub color_help {
    my $use_colors = shift;
    if ( $use_colors eq 'off' ) {
        $CMD_HELP =~ s/<c>|<\/c>//g;
    } else {
        my $cc_cyan    = weechat::color('cyan');
        my $cc_white   = weechat::color('white');
        my $cc_brown   = weechat::color('brown');
        my $cc_red     = weechat::color('red');
        my $cc_default = weechat::color('default');
        $CMD_HELP =~ s/default: '(.*)?'/default: '$cc_cyan$1$cc_default'/g;
        $CMD_HELP =~ s/'(on|off|0|1)?'/'$cc_cyan$1$cc_default'/g;
        $CMD_HELP =~ s/(\/$SCRIPT)/$cc_red$1$cc_default/g;
        foreach ( split( /\s+\|+\s+/, $COMPLETITION ), keys %SETTINGS ) {
            $CMD_HELP =~ s/(?|^(\s+)($_)([:,])|(\s+)($_)([:,])$)/$1$cc_brown$2$cc_default$3/gm;
        }
        $CMD_HELP =~ s/<c>(.*?)<\/c>/$cc_brown$1$cc_default/g;
        $CMD_HELP =~ s/(%[nNcCs])/$cc_cyan$1$cc_default/g;
    }
}

eval("defined weechat::info_get( 'version', '' )");
my $s = $@;

if ( $s =~ /Undefined subroutine/ ) {
    $_debug = sub { perl_debug( $_[0] ); };
    $_print = sub { perl_print( $_[0] ); };
    
    color_help('off');

    if ( not defined $ARGV[0] ) {
        $_print->($USAGE);
    } elsif ( $ARGV[0] eq 'help' ) {
        $_print->( help() );
    } elsif ( $ARGV[0] eq 'changelog' ) {
        $_print->( changelog(1) );
    } else {
        $_print->($USAGE);
    }
} else {
    color_help('on');

    init_weechat_script();
}

# setlocal equalprg=perltidy\ -q\ -l=160
# vim: tw=160 ai ts=4 sts=4 et sw=4  foldmethod=marker :
