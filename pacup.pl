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
use Pod::Usage;
use Term::ANSIColor;

my $TMPDIR = $ENV{'TMPDIR'} || '/tmp';
my $PACUP_DIR = tempdir 'pacup.XXXXXX', DIR => $TMPDIR;

my $REPOLOGY_API_ROOT = 'https://repology.org/api/v1/project';
my @HASHTYPES = qw(b2 md5 sha1 sha224 sha256 sha384 sha512);

my $opt_help = 0;
my $opt_ship = 0;
my $opt_origin_remote = 'origin';
my $opt_custom_version;
my $opt_push_force = 0;

sub info ($text) {
    say colored( '[', 'bold' ), colored( '+', 'bold green' ),
        colored( '] INFO: ', 'bold' ), $text;
}

sub warner ($text) {
    say STDERR colored( '[', 'bold' ), colored( '*', 'bold yellow' ),
        colored( '] WARNING: ', 'bold' ), $text;
}

sub error ($text) {
    say STDERR colored( '[', 'bold' ), colored( '!', 'bold red' ),
        colored( '] ERROR: ', 'bold' ), $text;
}

sub throw ($text) {
    error $text;
    exit 1;
}

sub subtext ($text) {
    say colored( '    [', 'bold' ), colored( '>', 'bold blue' ),
        colored( '] ', 'bold' ), $text;
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

END {
    info 'Cleaning up' unless ( $opt_help || !@ARGV );
    rmtree $PACUP_DIR;
}

sub check_deps {
    my @deps = qw(dpkg git sha256sum);
    my $path = $ENV{'PATH'} || '/bin:/usr/bin';
    my @pathdirs = split /:/, $path;
    for my $dep (@deps) {
        my $found = 0;
        for my $dir (@pathdirs) {
            my $try_path = $dir . '/' . $dep;
            next unless -x $try_path;
            $found = 1;
            last;
        }
        throw 'Dependency ' . colored( $dep, 'bold' ) . ' not found'
            unless $found;
    }
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
    } else {
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
    } else {
        @arr = getarr "source", $lines;
    }
    return @arr if @arr;
}

sub get_sumarr ( $hashtype, $carch, $lines ) {
    my @arr;
    if ( grep m/^${hashtype}sums_$carch=\(/, @$lines ) {
        @arr = getarr "${hashtype}sums_$carch", $lines;
    } else {
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
    throw 'Could not fetch repology' unless $response->is_success;

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
    throw 'Could not find Repology entry that meets the requirements';
}

sub fetch_source_entry ( $ua, $url, $outfile ) {
    my $response = $ua->get($url);
    throw "Could not fetch $url" unless $response->is_success;

    open my $fh, '>', $outfile or throw "Could not open $outfile: $!";
    print $fh $response->decoded_content
        or throw "Could not write to $outfile: $!";
    close $fh or throw "Could not close $outfile: $!";

    return $outfile;
}

sub calculate_hash ( $file, $hashtype ) {
    my $output = qx(${hashtype}sum $file)
        or throw "Could not calculate ${hashtype}sum of $file";
    my ($hash) = split ' ', $output;
    return $hash;
}

sub fetch_sources ( $ua, $pkgdir, $sources, $lines ) {
    my @lines = @$lines;
    local $CWD = $pkgdir;
    for my $entry (@$sources) {
        my $url = $entry->{'url'};
        my $file = basename $url;
        info "Downloading " . colored( $file, 'bold magenta' );
        fetch_source_entry $ua, $url, $file;
        for my $hashtype (@HASHTYPES) {
            my $oldhash = $entry->{$hashtype} || next;
            subtext "Calculating ${hashtype}sum for source entry";
            my $newhash = calculate_hash $file, $hashtype;
            s/$oldhash/$newhash/ for @lines;
        }
    }
    return @lines;
}

sub main ($infile) {
    -f $infile or throw "Not a file: " . colored( $infile, 'bold' );
    -w $infile or throw "File is not writable: " . colored( $infile, 'bold' );

    my $pacscript = basename $infile;
    my @lines;
    {
        open my $fh, '<', $infile or throw "Could not open $infile: $!";
        chomp( @lines = <$fh> );
        close $fh or throw "Could not close $infile: $!";
    }

    info "parsing $infile";

    my $pkgname = getvar 'pkgname', \@lines;
    throw 'Could not find pkgname' unless $pkgname;
    subtext "Found pkgname: " . colored( $pkgname, 'cyan' );

    my $pkgver = getvar 'pkgver', \@lines;
    throw 'Could not find pkgver' unless $pkgver;
    subtext "Found pkgver: " . colored( $pkgver, 'yellow' );

    my $newestver;
    my $ua = LWP::UserAgent->new( show_progress => 1 );
    if ($opt_custom_version) {
        $newestver = $opt_custom_version;
    } else {
        my @repology = getarr 'repology', \@lines;
        throw 'Could not find repology' unless @repology;
        @repology = map { $_ = get_sourced $_, $infile } @repology;
        subtext 'Found repology info';

        my %repology_filters = parse_repology \@repology;

        info 'Querying Repology';
        my $response = query_repology $ua, \%repology_filters;
        $newestver = repology_get_newestver $response, \%repology_filters,
            $pkgver;
    }
    subtext "Current version: " . colored( $pkgver, 'red' );
    subtext "Newest version: " . colored( $newestver, 'green' );
    system "dpkg --compare-versions $pkgver ge $newestver";
    info 'nothing to do' and return 1 if $? == 0;

    return 1
        unless ask_yes "Proceed with updating "
        . colored( $pkgname, 'magenta' ) . " to "
        . colored( $newestver, 'green' ) . "?";
    info 'Updating pkgver';
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
            subtext 'Found source ' . colored( $entry->{'url'}, 'underline' );
        }

        @sourceList = grep check_hashes, @sourceList;

        push @allSources, @sourceList;
    }
    throw 'Could not find sources' unless @allSources;

    info "Fetching sources for " . colored( $pkgname, 'bold blue' );
    my $pkgdir = tempdir "$pkgname.XXXXXX", DIR => $PACUP_DIR;
    @lines = fetch_sources $ua, $pkgdir, \@allSources, \@lines;

    info "updating " . colored( $pacscript, 'bold yellow' );
    {
        open my $fh, '>', $infile or throw "Could not open $infile: $!";
        print $fh ( join "\n", @lines ) . "\n"
            or throw "Could not write to $infile: $!";
        close $fh or throw "Could not close $infile: $!";
    }

    if ( -x '/usr/bin/pacstall' ) {
        info "Installing from $pacscript";
        system "pacstall -PI $infile";
        return unless ask "does $pkgname work?";
    } else {
        warner "Pacstall is not installed or not executable!";
    }

    return 1 unless $opt_ship;

    my $commit_msg = qq/upd($pkgname): \\\`$pkgver\\\` -> \\\`$newestver\\\`/;

    system qq/git add "$infile"/;
    my $current_branch = `git rev-parse --abbrev-ref HEAD`;
    chomp($current_branch);
    if (run( EXIT_ANY,
            "git show-ref --verify --quiet refs/heads/ship-$pkgname" ) == 0
        )
    {
        return unless ask_yes "Delete existing branch ship-$pkgname?";
        if ( $current_branch eq "ship-$pkgname" ) {
            throw "Currently on ship-$pkgname";
        } else {
            system "git branch -D ship-$pkgname";
        }
    }
    system "git checkout -b ship-$pkgname";
    system qq/git commit -m "$commit_msg"/;
    my $force = $opt_push_force ? '--force' : '';
    system "git push -u $opt_origin_remote ship-$pkgname $force";

    if ( ask
        'Create PR? (must have gh installed and authenticated to GitHub)' )
    {
        system qq(gh pr create --title "$commit_msg" --body "");
    }

    info "done!";
    return 1;
}

GetOptions(
    'help|?' => \$opt_help,
    'ship' => \$opt_ship,
    'origin-remote=s' => \$opt_origin_remote,
    'custom-version|c=s' => \$opt_custom_version,
    'push-force' => \$opt_push_force,
) or pod2usage(2);

pod2usage(0) if $opt_help;
pod2usage(1) if !@ARGV;

check_deps();
for my $infile (@ARGV) {
    main $infile;
}

__END__

=head1 NAME

pacup - Pacscript Updater

=head1 SYNOPSIS

pacup [options]

=head1 DESCRIPTION

Pacup (Pacscript Updater) is a maintainer helper tool to help maintainers update their pacscripts. It semi-automates the tedious task of updating pacscripts, and aims to make it a fun process for the maintainer! Originally written in Python, now in Perl.

=head1 OPTIONS

=over 4

=item B<-h, -?, --help>

Print this help message.

=item B<-s, --ship>

Create a new branch and push the changes to git.

=item B<-o, --origin-remote>

Specify the remote repository. Default is 'origin'.

=item B<-c, --custom-version>

Set a custom version for the package to fetch, instead of querying Repology.

=item B<-p, --push-force>

Force push to the branch, overwriting any existing one.

=back

=head1 EXAMPLE

    pacup -s packages/github-desktop-deb/github-desktop-deb.pacscript

=head1 AUTHOR

Vigress - <vig@disroot.org>

=head1 VERSION

Pacup (Perl edition) version 0.0.1

=cut

# vim: set ts=4 sw=4 et:
