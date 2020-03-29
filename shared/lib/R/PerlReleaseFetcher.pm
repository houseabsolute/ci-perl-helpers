package R::PerlReleaseFetcher;

use v5.30.1;
use strict;
use warnings 'FATAL' => 'all';
use feature 'postderef', 'signatures';
use autodie qw( :all );
use namespace::autoclean;

use H::PerlRelease;
use List::AllUtils qw( max );
use MetaCPAN::Client;
use Specio::Declare;
use Specio::Library::Builtins;

use Moose::Role;
## no critic (TestingAndDebugging::ProhibitNoWarnings)
no warnings 'experimental::postderef', 'experimental::signatures';
## use critic

has _client => (
    is      => 'ro',
    isa     => object_can_type( methods => ['release'] ),
    lazy    => 1,
    default => sub { MetaCPAN::Client->new },
);

has _perl_releases => (
    is      => 'ro',
    isa     => t( 'ArrayRef', of => object_isa_type('H::PerlRelease') ),
    lazy    => 1,
    builder => '_build_perl_releases',
);

sub _build_perl_releases ($self) {
    my $releases = $self->_client->release( { distribution => 'perl' } );
    die 'No releases for perl?' unless $releases->total;

    my %releases;
    while ( my $r = $releases->next ) {
        next unless $r->name =~ /^perl-5/;
        next if $r->name     =~ /RC/;
        my $parsed = _parse_numeric_version( $r->version )
            or next;
        push $releases{ $parsed->{minor} }->@*, $parsed;
    }

    for my $minor ( keys %releases ) {
        $releases{$minor}
            = [ sort { $a->{patch} <=> $b->{patch} } $releases{$minor}->@* ];
        $releases{$minor}[-1]{is_latest_in_minor} = 1;
    }

    return [
        map { H::PerlRelease->new($_) }
        map { $_->@* } values %releases
    ];
}

sub _parse_numeric_version ($version) {
    return if $version =~ /^v/;

    my ( $major, $minor, $patch ) = $version =~ /^(\d+)\.(0\d\d)(\d\d\d)$/
        or return;
    $_ += 0 for $minor, $patch;

    return {
        version => "$major.$minor.$patch",
        major   => $major,
        minor   => $minor,
        patch   => $patch,

        # Will be changed to 1 for appropriate releases above.
        is_latest_in_minor => 0,
    };
}

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _latest_stable_perl ($self) {
    my %perls = map { $_->numeric_version => $_ }
        grep { $_->is_stable } $self->_perl_releases->@*;
    return $perls{ max keys %perls };
}
## use critic

1;
