package Pacup::Repology;

use strict;
use warnings;
use feature qw(signatures);
no warnings qw(experimental::signatures);

use Pacup::Util;
use Data::Compare;
use JSON 'decode_json';

use base 'Exporter';
our @EXPORT = qw(parse_repology query_repology repology_get_newestver);

my $REPOLOGY_API_ROOT = 'https://repology.org/api/v1/project';
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

sub repology_get_newestver ( $response, $filters, $oldver ) {
    my $decoded = decode_json $response;
    for my $entry (@$decoded) {
        next if grep /^$entry->{'repo'}$/, @banned_repos;

        my %filtered;
        for my $key (%$filters) {
            if ( exists $entry->{$key} && $entry->{$key} eq $filters->{$key} )
            {
                $filtered{$key} = $entry->{$key};
            }
        }
        next unless Compare \%filtered, $filters;
        my $newver = $entry->{'version'};
        if ( $entry->{'status'} eq 'newest' ) {
            return $newver;
        }

        system "dpkg --compare-versions $newver gt $oldver";
        $? == 0 or next;

        return $newver;
    }
    throw 'Could not find Repology entry that meets the requirements';
}
