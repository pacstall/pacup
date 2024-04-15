package Pacup::Util;

use strict;
use warnings;
use feature qw(say signatures);
no warnings qw(experimental::signatures);
use Term::ANSIColor 'colored';

use base 'Exporter';
our @EXPORT = qw(ask ask_yes ask_wait error info subtext throw warner);

sub info ($text) {
    say '[', colored( '+', 'bold green' ), '] ',
        colored( 'INFO', 'bold' ), ': ', $text;
}

sub warner ($text) {
    say STDERR '[', colored( '*', 'bold yellow' ), '] ',
        colored( 'WARN', 'bold' ), ': ', $text;
}

sub error ($text) {
    say STDERR '[', colored( '!', 'bold red' ), '] ',
        colored( 'ERROR', 'bold' ), ': ', $text;
}

sub throw ($text) {
    error $text;
    exit 1;
}

sub subtext ($text) {
    say '    [', colored( '>', 'bold blue' ), '] ', $text;
}

sub ask ($text) {
    print $text, colored( ' [', 'bold' ), colored( 'y', 'green' ),
        colored( '/', 'bold' ), colored( 'N', 'bold red' ),
        colored( '] ', 'bold' );
    chomp( my $answer = <STDIN> );
    return $answer =~ /ye?s?/i;
}

sub ask_yes ($text) {
    print $text, colored( ' [', 'bold' ), colored( 'Y', 'bold green' ),
        colored( '/', 'bold' ), colored( 'n', 'red' ),
        colored( '] ', 'bold' );
    chomp( my $answer = <STDIN> );
    return !( $answer =~ /no?/i );
}

sub ask_wait ($text) {
    while (1) {
        print $text, colored( ' [', 'bold' ),
            colored( 'y', 'bold green' ), colored( '/', 'bold' ),
            colored( 'n', 'bold red' ), colored( '] ', 'bold' );
        chomp( my $answer = <STDIN> );
        if ( $answer =~ /ye?s?/i ) {
            return 1;
        } elsif ( $answer =~ /no?/i ) {
            return 0;
        }
    }
}

1;
