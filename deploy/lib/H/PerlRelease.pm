package H::PerlRelease;

use v5.30.1;
use strict;
use warnings;
use feature 'postderef', 'signatures';
use warnings 'FATAL' => 'all';
use autodie qw( :all );
use namespace::autoclean;

use Specio::Library::Builtins;

use Moose;
## no critic (TestingAndDebugging::ProhibitNoWarnings)
no warnings 'experimental::postderef', 'experimental::signatures';
## use critic

has version => (
    is       => 'ro',
    isa      => t('Str'),
    required => 1,
);

has major => (
    is       => 'ro',
    isa      => t('Int'),
    required => 1,
);

has minor => (
    is       => 'ro',
    isa      => t('Int'),
    required => 1,
);

has patch => (
    is       => 'ro',
    isa      => t('Int'),
    required => 1,
);

has numeric_version => (
    is      => 'ro',
    isa     => t('Num'),
    lazy    => 1,
    default => sub ($self) {
        return
            sprintf( '%d.%03d%03d', $self->major, $self->minor, $self->patch )
            + 0;
    },
);

has maj_min => (
    is      => 'ro',
    isa     => t('Str'),
    lazy    => 1,
    default => sub ($self) { join q{.}, $self->major, $self->minor },
);

has is_stable => (
    is      => 'ro',
    isa     => t('Bool'),
    lazy    => 1,
    default => sub ( $self ) { !( $self->minor % 2 ) },
);

has is_latest_in_minor => (
    is       => 'ro',
    isa      => t('Bool'),
    required => 1,
);

__PACKAGE__->meta->make_immutable;

1;
