package T::PrepForTests;

use strict;
use warnings FATAL => 'all';
use autodie qw( :all );

use Path::Tiny qw( path );

use Moo;
use MooX::StrictConstructor;

with 'R::HelperScript';

sub run {
    my $self = shift;

    $self->_debug_step;

    my $dir = $self->_pushd( $self->extracted_dist_dir );

    if ( path('Build.PL')->exists ) {
        $self->_with_brewed_perl_perl5lib(
            $self->runtime_perl,
            sub {
                $self->_system(
                    $self->_brewed_perl( $self->runtime_perl ),
                    'perl',
                    'Build.PL',
                );
                $self->_system(
                    $self->_brewed_perl( $self->runtime_perl ),
                    'perl',
                    'Build',
                );
            },
        );
    }
    elsif ( path('Makefile.PL')->exists ) {
        $self->_with_brewed_perl_perl5lib(
            $self->runtime_perl,
            sub {
                $self->_system(
                    $self->_brewed_perl( $self->runtime_perl ),
                    'perl',
                    'Makefile.PL',
                );
                $self->_system(
                    $self->make,
                    '-j', 4,
                );
            },
        );
    }
    else {
        $self->_show_env;
        die 'This distro does not have a Makefile.PL or Build.PL file!';
    }

    return 0;
}

1;
