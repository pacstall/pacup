#!/usr/bin/env perl
our $VERSION = '0.0.1';

use strict;
use warnings;
use feature qw(say signatures);
no warnings qw(experimental::signatures);

use Data::Compare;
use Data::Dumper;
use File::Basename 'basename';
use File::chdir;
use File::Path qw(make_path rmtree);
use File::Temp 'tempdir';
use Getopt::Long;
use IPC::System::Simple qw(run EXIT_ANY);
use JSON 'decode_json';
use LWP::UserAgent;

my $SCRIPT    = basename $0;
my $TMPDIR    = $ENV{'TMPDIR'} || '/tmp';
my $PACUP_DIR = tempdir 'pacup.XXXXXX', DIR => $TMPDIR;

my $REPOLOGY_API_ROOT = 'https://repology.org/api/v1/project';
my @HASHTYPES         = qw(b2 md5 sha1 sha224 sha256 sha384 sha512);

my $opt_ship   = 0;
my $opt_remote = 'origin';
my $opt_custom_version;
my $opt_push_force = 0;

sub throw ($action) {
    say STDERR "$SCRIPT: could not $action: $!" and exit 1;
}

sub msg ($text) {
    say "$SCRIPT: $text";
}

sub ask ($text) {
    print "$SCRIPT: $text [y/N] ";
    chomp( my $answer = <STDIN> );
    return $answer =~ /ye?s?/i;
}

END {
    msg 'cleaning up...';
    rmtree $PACUP_DIR;
}

sub getvar ( $name, $lines ) {
    my @lines = @$lines;
    my $var;
    for (@lines) {
        s/^$name=// and m/^ ["'] ([^"']+) ["'] $/x and $var = $1;
    }
    return $var if $var && $var !~ /^\s*$/;
}

sub getarr ( $name, $lines ) {
    my @lines = @$lines;
    my @arr;
OUTER: while ( my ( $i, $line ) = each @lines ) {
        $line =~ /^$name=\(/ or next;
        for ( @lines[ $i .. $#lines ] ) {
            s/^$name=\(//;
            push @arr, m/ \s* ["'] ([^"']+) ["'] \s* \)? /gx;
            last OUTER if /\)$/;
        }
    }
    return @arr if @arr;
}

sub geturl ($entry) {
    my $url;
    if ( $entry =~ /::/ ) {
        ( undef, $url ) = split /::/, $entry;
    }
    else {
        $url = $entry;
    }
    return $url;
}

sub get_sourced ( $name, $infile, $carch = 'amd64' ) {
    my $output
        = qx(env CARCH=$carch bash -e -c 'source "$infile" && printf \%s "$name"');
    return $output;
}

sub get_sourcearr ( $carch, $lines ) {
    my @arr;
    if ( grep m/^source_$carch=\(/, @$lines ) {
        @arr = getarr "source_$carch", $lines;
    }
    else {
        @arr = getarr "source", $lines;
    }
    return @arr if @arr;
}

sub get_sumarr ( $hashtype, $carch, $lines ) {
    my @arr;
    if ( grep m/^${hashtype}sums_$carch=\(/, @$lines ) {
        @arr = getarr "${hashtype}sums_$carch", $lines;
    }
    else {
        @arr = getarr "${hashtype}sums", $lines;
    }
    return @arr if @arr;
}

sub check_hashes {
    for my $hashtype (@HASHTYPES) {
        my $hash = $_->{$hashtype};
        defined $hash or next;
        return 0 if $hash eq 'SKIP';
    }
    return 1;
}

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
    throw 'fetch repology' unless $response->is_success;
    return $response->decoded_content;
}

sub repology_get_newestver ( $response, $filters, $oldver ) {
    my $decoded = decode_json $response;
    for my $entry (@$decoded) {
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
    throw 'find Repology entry that meets the requirements';
}

sub fetch_source_entry ( $ua, $url, $outfile ) {
    my $response = $ua->get($url);
    throw "fetch $url" unless $response->is_success;

    open my $fh, '>', $outfile;
    print $fh $response->decoded_content or throw "write to $outfile";
    close $fh;

    return $outfile;
}

sub calculate_hash ( $file, $hashtype ) {
    my $output = qx(${hashtype}sum $file)
        or throw "calculate ${hashtype}sum of $file";
    my ($hash) = split ' ', $output;
    return $hash;
}

sub fetch_sources ( $ua, $pkgdir, $sources, $lines ) {
    my @lines = @$lines;
    local $CWD = $pkgdir;
    for my $entry (@$sources) {
        my $url  = $entry->{'url'};
        my $file = basename $url;
        msg "fetching $url as $file...";
        fetch_source_entry $ua, $url, $file;
        for my $hashtype (@HASHTYPES) {
            my $oldhash = $entry->{$hashtype} || next;
            msg "calculating $hashtype for $file...";
            my $newhash = calculate_hash $file, $hashtype;
            s/$oldhash/$newhash/ for @lines;
        }
    }
    return @lines;
}

sub main ($infile) {
    my $pacscript = basename $infile;
    my @lines;
    {
        open my $fh, '<', $infile;
        chomp( @lines = <$fh> );
        close $fh;
    }

    msg "parsing $infile...";

    my $pkgname = getvar 'pkgname', \@lines;
    throw 'find pkgname' unless $pkgname;
    msg "found pkgname: $pkgname";

    my $pkgver = getvar 'pkgver', \@lines;
    throw 'find pkgver' unless $pkgver;
    msg "found pkgver: $pkgver";

    my $newestver;
    my $ua = LWP::UserAgent->new( show_progress => 1 );
    if ($opt_custom_version) {
        $newestver = $opt_custom_version;
    }
    else {
        my @repology = getarr 'repology', \@lines;
        throw 'find repology' unless @repology;
        @repology = map { $_ = get_sourced $_, $infile } @repology;
        msg 'found repology';

        my %repology_filters = parse_repology \@repology;

        msg 'querying Repology...';
        my $response = query_repology $ua, \%repology_filters;
        $newestver = repology_get_newestver $response, \%repology_filters,
            $pkgver;
    }
    msg "current version: $pkgver";
    msg "newest version: $newestver";
    system "dpkg --compare-versions $pkgver ge $newestver";
    msg 'nothing to do' and return 1 if $? == 0;

    msg 'updating pkgver...';
    s/\Q$pkgver\E/$newestver/ for @lines;
    {
        open my $fh, '>', $infile;
        print $fh ( join "\n", @lines ) . "\n" or throw "write to $infile";
        close $fh;
    }

    my @arches = getarr 'arch', \@lines;
    @arches = qw(amd64) unless @arches;

    my @allSources;
    for my $arch (@arches) {
        my @sourceList;
        my @source = get_sourcearr "$arch", \@lines;
        while ( my ( $i, $entry ) = each @source ) {
            my %edict;
            $edict{'url'} = geturl $entry;
            for my $hashtype (@HASHTYPES) {
                my @sums = get_sumarr $hashtype, $arch, \@lines;
                next if grep { $_ eq 0 } @sums;
                $edict{$hashtype} = $sums[$i];
            }
            push @sourceList, \%edict;
        }

        @sourceList = grep { $_->{'url'} =~ /pkgver/ } @sourceList;
        for my $entry (@sourceList) {
            $entry->{'url'} = get_sourced $entry->{'url'}, $infile, $arch;
            msg 'found source url: ' . $entry->{'url'};
        }

        @sourceList = grep check_hashes, @sourceList;

        push @allSources, @sourceList;
    }
    throw 'find sources' unless @allSources;

    msg "Fetching sources for $pkgname...";
    my $pkgdir = tempdir "$pkgname.XXXXXX", DIR => $PACUP_DIR;
    @lines = fetch_sources $ua, $pkgdir, \@allSources, \@lines;

    msg "updating $pacscript...";
    {
        open my $fh, '>', $infile;
        print $fh ( join "\n", @lines ) . "\n" or throw "write to $infile";
        close $fh;
    }

    msg "installing from $pacscript...";
    system "pacstall -PI $infile";

    return   unless ask "does $pkgname work?";
    return 1 unless $opt_ship;

    my $commit_msg = qq/upd($pkgname): \\\`$pkgver\\\` -> \\\`$newestver\\\`/;

    system qq/git add "$infile"/;
    my $current_branch = `git rev-parse --abbrev-ref HEAD`;
    chomp($current_branch);
    if (run( EXIT_ANY,
            "git show-ref --verify --quiet refs/heads/ship-$pkgname" ) == 0
        )
    {
        return unless ask "Delete existing branch ship-$pkgname?";
        if ( $current_branch eq "ship-$pkgname" ) {
            say "FATAL: currently on ship-$pkgname";
            exit 1;
        }
        else {
            system "git branch -D ship-$pkgname";
        }
    }
    system "git checkout -b ship-$pkgname";
    system qq/git commit -m "$commit_msg"/;
    my $force = $opt_push_force ? '--force' : '';
    system "git push -u $opt_remote ship-$pkgname $force";

    if ( ask
        'create PR? (must have gh installed and authenticated to GitHub)' )
    {
        system qq(gh pr create --title "$commit_msg" --body "");
    }

    say "$SCRIPT: done";
    return 1;
}

GetOptions(
    'ship'               => \$opt_ship,
    'remote=s'           => \$opt_remote,
    'custom-version|c=s' => \$opt_custom_version,
    'push-force'         => \$opt_push_force,
);

for my $infile (@ARGV) {
    -f $infile or die "$SCRIPT: $infile: not a file\n";
    main $infile;
}

# vim: set ts=4 sw=4 et:
