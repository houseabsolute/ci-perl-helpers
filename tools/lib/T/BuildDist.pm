package T::BuildDist;

use strict;
use warnings FATAL => 'all';
use autodie qw( :all );

use File::Copy qw( copy );
use Path::Tiny qw( path );

use Moo;
use MooX::StrictConstructor;

with 'R::HelperScript';

sub run {
    my $self = shift;

    $self->_debug_step;

    ## no critic (ControlStructures::ProhibitCascadingIfElse)
    if ( $self->is_dzil ) {
        $self->_build_dzil;
    }
    elsif ( $self->is_minilla ) {
        $self->_build_minilla;
    }
    elsif ( $self->has_build_pl ) {
        $self->_build_build_pl;
    }
    elsif ( $self->has_makefile_pl ) {
        $self->_build_build_pl;
    }
    else {
        die 'I have no idea how to build this distro.'
            . ' It is not using dzil or minilla and it does not have a Build.PL or Makefile.PL file.';
    }

    my $tarball     = ( glob '*.tar.gz' )[0];
    my $dist_tar_gz = $self->artifact_dir->child('dist.tar.gz');

    # Rename will fail if the target dir is a docker-mounted volume.
    $self->_debug("Copying $tarball to $dist_tar_gz");
    copy( $tarball => $dist_tar_gz );

    return 0;
}

sub _build_dzil {
    my $self = shift;

    # The working dir might be something like '~/project` and pushd can't
    # handle the '~', apparently.
    my $dir = $self->_pushd( $self->checkout_dir );
    $self->_with_brewed_perl_perl5lib(
        $self->tools_perl,
        sub {
            $self->_system(
                $self->_brewed_perl( $self->tools_perl ),
                $self->_perl_local_script( $self->tools_perl, 'dzil' ),
                'build',
            );
        },
    );

    return undef;
}

sub _build_minilla {
    my $self = shift;

    $self->_with_brewed_perl_perl5lib(
        $self->tools_perl,
        sub {
            $self->_system(
                $self->_brewed_perl( $self->tools_perl ),
                $self->_perl_local_script( $self->tools_perl, 'minil' ),
                'dist',
                '--no-test',
            );
        },
    );

    return undef;
}

sub _build_build_pl {
    my $self = shift;

    $self->_with_brewed_perl_perl5lib(
        $self->tools_perl,
        sub {
            $self->_system(
                $self->_brewed_perl( $self->tools_perl ),
                'perl',
                'Build.PL',
            );
            $self->_system(
                $self->_brewed_perl( $self->tools_perl ),
                './Build',
                'manifest',
            );
            $self->_system(
                $self->_brewed_perl( $self->tools_perl ),
                './Build',
                'distdir',
            );
        },
    );

    return undef;
}

sub _build_makefile_pl {
    my $self = shift;

    $self->_with_brewed_perl_perl5lib(
        $self->tools_perl,
        sub {
            $self->_system(
                $self->_brewed_perl( $self->tools_perl ),
                'perl',
                'Makefile.PL',
            );
            $self->_with_perl5lib(
                $self->tools_perl,
                'make',
                'manifest',
            );
            $self->_with_perl5lib(
                $self->tools_perl,
                'make',
                'dist',
            );
        },
    );

    return undef;
}

1;
