package Pacup::Repology;

use strict;
use warnings qw(all -experimental::signatures);
use feature qw(signatures);

use Pacup::Util;
use Data::Compare;
use Dpkg::Version qw(version_compare_relation REL_GT REL_LT);
use IPC::System::Simple qw(system);
use List::Util 'reduce';
use List::MoreUtils 'all';
use JSON 'decode_json';
use open ':std', ':encoding(UTF-8)';

use base 'Exporter';
our @EXPORT = qw(parse_repology query_repology repology_get_newestver);

my $REPOLOGY_API_ROOT = 'https://repology.org/api/v1/project';

# List of repositories not to be used for version detection.
# As can be inferred, we don't like Windows versions.
my @BANNED_REPOS = qw(
    appget
    baulk
    chocolatey
    cygwin
    just-install
    scoop
    winget
);

sub parse_repology ($arr) {
    return map { split ': ', $_, 2 } @$arr;
}

sub query_repology ( $ua, $filters ) {
    my $project = $filters->{'project'};
    delete $filters->{'project'};
    $ua->agent(
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'
    );

    my $response = $ua->get("$REPOLOGY_API_ROOT/$project");
    throw 'Could not fetch repology' unless $response->is_success;

    return $response->decoded_content;
}

sub repology_get_newestver ( $response, $filters, $oldver, $action ) {
    my $decoded = decode_json($response);
    my @filtered;
    my %version_count;

    foreach my $entry (@$decoded) {
        next if grep /^\Q$entry->{'repo'}\E$/, @BANNED_REPOS;
        my $is_match
            = all { exists $entry->{$_} && $entry->{$_} eq $filters->{$_} }
            keys %$filters;
        next unless $is_match;
        next if ( $entry->{'version'} eq 'HEAD' );
        if ( $action eq 'display' ) {
            my $json_text = JSON->new->pretty->encode($entry);
            $json_text =~ s/^/\t/mg;
            print $json_text;
        }
        push @filtered, $entry;
        if ( $entry->{'status'} ne 'newest' ) {
            next
                unless ( $filters->{'status'}
                && $filters->{'status'} eq 'devel' )
                || exists $filters->{'repo'};
        }
        $version_count{ $entry->{'version'} }++;
    }

    my $newver = reduce {
        if ( version_compare_relation $a, REL_GT, $b ) {
            $a;
        } elsif ( version_compare_relation $a, REL_LT, $b ) {
            $b;
        } else {
            $version_count{$a} >= $version_count{$b} ? $a : $b;
        }
    } keys %version_count;

    foreach my $entry (@filtered) {
        if ( $entry->{'version'} eq $newver ) {
            return $newver;
        }
    }
    throw 'Could not find Repology entry that meets the requirements';
}

1;
