package T::InstallPrereqs;

use strict;
use warnings FATAL => 'all';
use autodie qw( :all );

use CPAN::Meta;
use Getopt::Long;
use Path::Tiny qw( path );

use Moo;
use MooX::StrictConstructor;

with 'R::HelperScript';

sub run {
    my $self = shift;

    $self->_debug_step;

    my $extra;
    GetOptions( 'extra-prereqs:s' => \$extra );

    my $dir = $self->_pushd( $self->extracted_dist_dir );

    my @with_develop = $self->test_xt ? '--with-develop' : ();
    $self->cpan_install(
        'runtime-perl',
        @with_develop,
        '--with-configure',
        '--with-recommends',
        '--with-suggests',
        '--cpanfile', $self->cache_dir->child('prereqs-cpanfile'),
    );

    if ($extra) {
        my @extra = split /,/, $extra;
        $self->cpan_install(
            'runtime-perl',
            split /,/, $extra,
        );
    }

    my @coverage;
    if ( $self->coverage ) {
        @coverage = (
            '--feature', 'coverage',
            '--feature', 'coverage-' . lc $self->coverage,
        );
    }

    # This will already be installed in non-blead Docker images but not for
    # other types of builds.
    $self->cpan_install(
        'runtime-perl',
        '--feature', 'runtime',
        @coverage,
        '--cpanfile', $self->tools_dir->child('cpanfile'),
    );

    return 0;
}

1;
