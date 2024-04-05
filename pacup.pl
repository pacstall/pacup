#!/usr/bin/env perl
# dependencies on Debian:
# libfile-chdir-perl libipc-system-simple-perl libjson-perl
our $VERSION = '0.0.1';

use strict;
use warnings;
use autodie qw(:all);
use feature qw(say signatures);
no warnings qw(experimental::signatures);

#use Carp 'croak';
use Data::Dumper;
use File::Basename 'basename';
use File::chdir;
use File::Path qw(make_path rmtree);
use File::Temp 'tempdir';
use Getopt::Long qw(:config auto_version bundling);
use JSON 'decode_json';

my $SCRIPT    = basename $0;
my $TMPDIR    = ( $ENV{'TMPDIR'} or '/tmp' );
my $PACUP_DIR = tempdir 'pacup.XXXXXX', DIR => $TMPDIR;

my $REPOLOGY_API_ROOT = 'https://repology.org/api/v1/project';
my $USERAGENT =
'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';
my @HASHTYPES = qw(b2 md5 sha1 sha224 sha256 sha384 sha512);

sub throw ($action) {
    say STDERR "$SCRIPT: could not $action: $!" and exit 1;
}

sub msg ($text) {
    say "$SCRIPT: $text";
}

sub ask ($text) {
    print "$SCRIPT: $text [y/N] ";
    chomp( my $answer = <STDIN> );
    return 1 if ( lc $answer ) =~ /ye?s?/;
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
    my $output =
      qx(env CARCH=$carch bash -e -c 'source "$infile" && printf \%s "$name"');
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

sub query_repology ($filters) {
    my $project = $filters->{'project'};
    delete $filters->{'project'};

    my $response =
      qx(curl -H 'User-Agent: $USERAGENT' -s '$REPOLOGY_API_ROOT/$project');
    return $response;
}

sub repology_get_newestver ( $response, $filters ) {
    my $decoded = decode_json $response;
    for my $entry (@$decoded) {
        while ( my ( $key, $val ) = each %$filters ) {
            next unless $entry->{$key} eq $val;
        }
        next unless $entry->{'status'} eq 'newest';
        return $entry->{'version'};
    }
}

sub fetch_sources ( $pkgdir, $sources, $lines ) {
    my @lines = @$lines;
    local $CWD = $pkgdir;
    for my $entry (@$sources) {
        my $url  = $entry->{'url'};
        my $file = basename $url;
        msg "fetching $url as $file...";

        system qq(curl -fS#L -o "$file" "$url");
        throw "fetch $url" unless $? == 0;
        for my $hashtype (@HASHTYPES) {
            my $oldhash = $entry->{$hashtype};
            defined $oldhash or next;
            msg "calculating $hashtype for $file...";
            my ($newhash) = split ' ', qx(${hashtype}sum $file);
            s/$oldhash/$newhash/ for @lines;
        }
    }
    return @lines;
}

my $ship = 0;

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

    my @repology = getarr 'repology', \@lines;
    throw 'find repology' unless @repology;
    @repology = map { $_ = get_sourced $_, $infile } @repology;
    msg 'found repology';

    my %repology_filters = parse_repology \@repology;

    msg 'querying Repology...';
    my $response  = query_repology \%repology_filters;
    my $newestver = repology_get_newestver $response, \%repology_filters;
    msg "current version: $pkgver";
    msg "newest version: $newestver";
    {
        no autodie 'system';
        system "dpkg --compare-versions $pkgver ge $newestver";
        msg 'nothing to do' and exit if $? == 0;
    }

    msg 'updating pkgver...';
    s/$pkgver/$newestver/ for @lines;
    {
        open my $fh, '>', $infile;
        print $fh ( join "\n", @lines ) or throw "write to $infile";
        print $fh "\n";
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
    @lines = fetch_sources $pkgdir, \@allSources, \@lines;

    msg "updating $pacscript...";
    {
        open my $fh, '>', $infile;
        print $fh ( join "\n", @lines ) or throw "write to $infile";
        print $fh "\n";
        close $fh;
    }

    msg "installing from $pacscript...";
    {
        no autodie 'system';
        system "pacstall -PI $infile";
    }

    exit unless ask "does $pkgname work?";
    exit unless $ship;

    my $commit_msg = qq/upd($pkgname): `$pkgver` -> `$newestver`/;

    system qq/git add "$infile"/;
    system "git checkout -b ship-$pkgname master";
    system qq/git add $infile && git commit -m "$commit_msg"/;
    system "git push -u origin ship-$pkgname" or throw 'push changes';

    exit
      unless ask
      'create PR? (must have gh installed and authenticated to GitHub)';

    system qq(gh pr create --title "$commit_msg" --body "");

    say "$SCRIPT: done";
    return 1;
}

GetOptions 'ship' => \$ship;
for my $infile (@ARGV) {
    main $infile;
}

# vim: set ts=4 sw=4 et:
