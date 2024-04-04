#!/usr/bin/env perl
use strict;
use warnings;
use feature qw(say signatures);

#use Carp 'croak';
#use Data::Dumper;
use File::Basename 'basename';
use File::chdir;
use File::Path qw(make_path rmtree);
use File::Temp qw(tempfile tempdir);
use JSON 'decode_json';

my $SCRIPT    = basename $0;
my $PACUP_DIR = tempdir 'pacup.XXXXXX';

my $REPOLOGY_API_ROOT = 'https://repology.org/api/v1/project';
my $USERAGENT =
'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';
my @HASHTYPES = qw(b2 md5 sha1 sha224 sha256 sha384 sha512);

sub throw ($action) {
    print STDERR "$SCRIPT: could not $action: $!" and exit 1;
}

END {
    say "$SCRIPT: cleaning up...";
    rmtree $PACUP_DIR;
    throw "remove $PACUP_DIR" unless $? == 0;
}

sub getvar ( $name, $lines ) {
    for (@$lines) {
        s/^$name=// and m/^ ["'] ([^"']+) ["'] $/x and return $1;
    }
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
    return @arr;
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
    throw "get $name from $infile" unless $? == 0;
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
    return @arr;
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
    throw "query Repology" unless $? == 0;
    return $response;
}

sub repology_get_newestver ($response) {
    my $decoded = decode_json $response;
    for my $entry (@$decoded) {
        next unless $entry->{'status'} eq 'newest';
        return $entry->{'version'};
    }
}

sub main ($infile) {
    my $pacscript = basename $infile;
    my @lines;
    {
        open my $fh, '<', $infile or throw "open $infile";
        chomp( @lines = <$fh> );
        close $fh or throw "close $infile";
    }

    say "$SCRIPT: parsing $infile...";

    my $pkgname = getvar 'pkgname', \@lines;
    throw 'find pkgname' unless defined $pkgname;
    say "$SCRIPT: found pkgname: $pkgname";

    my $pkgver = getvar 'pkgver', \@lines;
    throw 'find pkgver' unless defined $pkgver;
    say "$SCRIPT: found pkgver: $pkgver";

    my @repology = getarr 'repology', \@lines;
    throw 'find repology' unless @repology;
    say "$SCRIPT: found repology";

    my %repology_filters = parse_repology \@repology;

    say "$SCRIPT: querying repology...";
    my $response  = query_repology \%repology_filters;
    my $newestver = repology_get_newestver $response;
    say "$SCRIPT: current version: $pkgver";
    say "$SCRIPT: newest version: $newestver";
    system "dpkg --compare-versions $pkgver ge $newestver";
    say "$SCRIPT: nothing to do" and return 0 if $? == 0;

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
                my @sums = getarr "${hashtype}sums_$arch", \@lines or next;
                $edict{$hashtype} = $sums[$i];
            }
            push @sourceList, \%edict;
        }

        @sourceList = grep { $_->{'url'} =~ /pkgver/ } @sourceList;
        for my $entry (@sourceList) {
            $entry->{'url'} = get_sourced $entry->{'url'}, $infile, $arch;
            say "$SCRIPT: found source url: " . $entry->{'url'};
        }

        @sourceList = grep check_hashes, @sourceList;

        push @allSources, @sourceList;
    }
    throw 'find sources' unless @allSources;

    say "$SCRIPT: Fetching sources for $pkgname...";
    my $pkgdir = tempdir "$pkgname.XXXXXX", DIR => $PACUP_DIR;
    local $CWD = $pkgdir;
    for my $entry (@allSources) {
        my $url  = $entry->{'url'};
        my $file = basename $url;
        say "$SCRIPT: fetching $url as $file...";

        system qq(curl -fS#L -o "$file" "$url");
        throw "fetch $url" unless $? == 0;
        for my $hashtype (@HASHTYPES) {
            my $oldhash = $entry->{$hashtype};
            defined $oldhash or next;
            say "$SCRIPT: calculating $hashtype for $file...";
            my ($newhash) = split ' ', qx(${hashtype}sum $file);
            throw "check $hashtype for $file" unless $? == 0;
            s/$oldhash/$newhash/ for @lines;
        }
    }
    say "$SCRIPT: updating $pacscript...";
    {
        open my $fh, '>', $infile or throw "open $infile";
        print $fh ( join '\n', @lines ) or throw "write to $infile";
        close $fh                       or throw "close $infile";
    }

    say "$SCRIPT: done";
    return 0;
}

main @ARGV;

# vim: set ts=4 sw=4 et:
