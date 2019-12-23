package D::PrintPerlsMatrix;

use v5.30.1;
use strict;
use warnings;
use feature 'postderef', 'signatures';
use warnings 'FATAL' => 'all';
use autodie qw( :all );
use namespace::autoclean;

use JSON::MaybeXS;
use List::AllUtils qw( max );
use Specio::Library::Builtins;

use Moose;
## no critic (TestingAndDebugging::ProhibitNoWarnings)
no warnings 'experimental::postderef', 'experimental::signatures';
## use critic

with 'MooseX::Getopt::Dashes', 'R::PerlReleaseFetcher', 'R::Tagger';

has pretty => (
    is            => 'ro',
    isa           => t('Bool'),
    default       => 0,
    documentation => 'Pretty print the JSON',
);

sub run ($self) {
    my $releases = $self->_perl_releases;

    my %perls;
    for my $r ( $self->_perl_releases->@* ) {
        push $perls{ $r->minor }->@*, $r;
    }

    my @minors   = sort     { $a <=> $b } keys %perls;
    my $last_dev = max grep { $_ % 2 } @minors;

    for my $minor ( sort { $a <=> $b } @minors ) {
        if ( $minor % 2 && $minor != $last_dev ) {
            delete $perls{$minor};
            next;
        }

        $perls{$minor}
            = [ sort { $a->numeric_version <=> $a->numeric_version }
                $perls{$minor}->@* ];

        # We only build 5.8.9 and 5.10.1 and the latest dev release. For all
        # other non-dev versions we build all releases.
        if ( $minor < 12 || $minor % 2 ) {
            $perls{$minor} = [ $perls{$minor}[-1] ];
        }
    }

    my %matrix;
    for my $r ( map { $_->@* } values %perls ) {
        my $key = 'perl_' . ( $r->version =~ s/\./_/gr );
        $matrix{$key} = {
            perl    => $r->version,
            threads => JSON()->false,
            tags    => $self->_tags_string($self->_tags_for_release( $r, 0 )),
        };
        $matrix{ $key . '_threads' } = {
            perl    => $r->version,
            threads => JSON()->true,
            tags    => $self->_tags_string($self->_tags_for_release( $r, 1 )),
        };
    }

    $matrix{perl_blead} = {
        perl => 'blead',
        tags => $self->_tags_string(
            $self->_tags_for_prefix( 'blead', 0 ),
            $self->_tags_for_prefix( 'blead', 1 ),
        ),
        threads => JSON()->false,
    };

    my $j = JSON()->new->canonical;
    $j->pretty if $self->pretty;
    say $j->encode( \%matrix )
        or die $!;

    return 0;
}

sub _tags_string ( $self, @tags ) {
    return join q{}, map {"$_\n"} @tags;
}

sub _tags_for_release ( $self, $r, $threads ) {
    if ( $r->minor % 2 ) {
        return $self->_tags_for_prefix( 'dev', $threads );
    }

    my @tags = $self->_tags_for_prefix( $r->version, $threads );

    if ( $r->is_latest_in_minor ) {
        my $majmin = join q{.}, $r->major, $r->minor;
        push @tags, $self->_tags_for_prefix( $majmin, $threads );
    }

    return @tags;
}

sub _tags_for_prefix ( $self, $prefix, $threads ) {
    return
        map { $prefix . ( $threads ? q{-threads} : q{} ) . q{-} . $_ }
        $self->image_versions->@*;
}

__PACKAGE__->meta->make_immutable;

1;
