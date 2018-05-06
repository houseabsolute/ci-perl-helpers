package T::InstallBuildDeps;

use strict;
use warnings FATAL => 'all';
use autodie qw( :all );

use Moo;
use MooX::StrictConstructor;

with 'R::HelperScript';

sub run {
    my $self = shift;

    $self->_debug_step;

    my $file = $self->cache_dir->child('build-deps-cpanfile');
    return 0 unless -s $file;
    $self->cpan_install( $self->tools_perl, '--cpanfile', $file );

    return 0;
}

1;
