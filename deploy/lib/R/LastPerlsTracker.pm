package R::LastPerlsTracker;

use v5.30.1;
use strict;
use warnings 'FATAL' => 'all';
use feature 'postderef', 'signatures';
use autodie qw( :all );
use namespace::autoclean;

use Moose::Role;
## no critic (TestingAndDebugging::ProhibitNoWarnings)
no warnings 'experimental::postderef', 'experimental::signatures';
## use critic

has _last_tag => (
    is      => 'ro',
    isa     => t('Str'),
    lazy    => 1,
    default => sub ($self) { $self->_last_perls_raw->{tag} // q{} },
);

has _last_perls => (
    is      => 'ro',
    isa     => t( 'HashRef', of => t('Bool') ),
    lazy    => 1,
    default => sub ($self) {
        return { map { $_ => 1 } $self->_last_perls_raw->{perls}->@* };
    },
);

has _last_perls_raw => (
    is      => 'ro',
    isa     => t( 'HashRef', of => t('Bool') ),
    lazy    => 1,
    checker => '_build_last_perls_raw',
);

has _last_perls_file => (
    is      => 'ro',
    isa     => t('Path'),
    lazy    => 1,
    default =>
        sub ($self) { $self->_artifacts_dir->child('last-perls.json') },
);

has _artifacts_dir => (
    is      => 'ro',
    isa     => t('Dir'),
    lazy    => 1,
    default => sub { path( $ENV{CI_ARTIFACT_STAGING_DIRECTORY} ) },
);

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _write_last_perls ( $self, $tag, @perls ) {
    my %content = (
        tag   => $tag,
        perls => [
            map  { $_->version }
            sort { $a->numeric_version <=> $b->numeric_version } @perls
        ],
    );

    $self->_last_perls_file->parent->mkpath( 0, 0755 );
    $self->_last_perls_file->spew( encode_json( \%content ) );
}
## use critic

sub _build_last_perls_raw ($self) {
    return { perls => [] } unless $self->_last_perls_file->exists;
    return decode_json( $self->_last_perls_file->slurp );
}

1;
