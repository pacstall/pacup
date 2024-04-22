package Pacup::Parser;

use strict;
use warnings qw(all -experimental::signatures);
use feature qw(signatures);

use IPC::System::Simple qw(capture);
use base 'Exporter';
our @EXPORT
    = qw(check_hashes getarr get_sourcearr get_sourced get_sumarr geturl getvar @HASHTYPES);

our @HASHTYPES = qw(b2 md5 sha1 sha224 sha256 sha384 sha512);

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
    my $output = capture
        qq(env CARCH=$carch bash -e -c 'source "$infile" && printf \%s "$name"');
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

1;
