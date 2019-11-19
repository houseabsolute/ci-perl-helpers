package T::InstallDynamicPrereqs;

use strict;
use warnings FATAL => 'all';
use autodie qw( :all );

use CPAN::Meta;
use Path::Tiny qw( path );
use Specio::Library::Path::Tiny;

use Moo;
use MooX::StrictConstructor;

with 'R::HelperScript';

has dynamic_prereqs_cpanfile => (
    is      => 'ro',
    isa     => t('Path'),
    default => sub { $_[0]->cache_dir->child('dynamic-prereqs-cpanfile') },
);

sub run {
    my $self = shift;

    $self->_debug_step;

    my $meta = $self->_load_cpan_meta_in( $self->extracted_dist_dir, 'META' );
    return 0 unless $meta->dynamic_config;

    my $mymeta
        = $self->_load_cpan_meta_in( $self->extracted_dist_dir, 'MYMETA' );
    $self->_write_cpanfile_from_meta(
        $self->dynamic_prereqs_cpanfile,
        $mymeta,
    );

    my $dir = $self->_pushd( $self->extracted_dist_dir );

    my @with_develop = $self->test_xt ? '--with-develop' : ();
    $self->cpan_install(
        'runtime-perl',
        '--with-recommends',
        '--with-suggests',
        '--cpanfile', $self->dynamic_prereqs_cpanfile,
    );

    return 0;
}

1;
