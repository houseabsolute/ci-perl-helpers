package T::PreTest;

use strict;
use warnings FATAL => 'all';
use autodie qw( :all );

use Getopt::Long;
use Path::Tiny qw( path );

use Moo;
use MooX::StrictConstructor;

with 'R::HelperScript';

sub run {
    my $self = shift;

    $self->_debug_step;

    my $perl;
    GetOptions( 'runtime-perl:s' => \$perl );

    $self->_install_blead($perl)
        if $perl =~ /^blead/;

    $self->_perl_v_to(
        'runtime-perl',
        $self->cache_dir->child('runtime-perl-version'),
    );

    my $dir = $self->_pushd( $self->extracted_dist_dir );
    $self->_system(
        'tar',
        '--extract',
        '--file',
        $self->_posix_path( $self->artifact_dir->child('dist.tar.gz') ),
        '--gzip',
        '--verbose',
        '--strip-components', 1
    );

    return 0;
}

sub _install_blead {
    my $self = shift;
    my $perl = shift;

    die 'Cannot install blead perl on Windows'
        if $^O eq 'MSWin32';

    if ( $^O eq 'darwin' ) {
        print
            "We always install the runtime-perl from scratch on macOS so $perl is already installed.\n"
            or die $!;
        return undef;
    }

    $self->_system(
        'perlbrew', 'install',
        '--verbose',
        ( $perl =~ /thread/ ? '--thread' : () ),
        '--notest',
        '--noman',
        '-j',   4,
        '--as', 'runtime-perl',
        'blead',
    );

    return undef;
}

1;
