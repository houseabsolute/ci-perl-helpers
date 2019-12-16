package T::RunCoverageReport;

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

    my $c = $self->coverage
        or return 0;

    if ( $c eq 'coveralls' ) {
        path('.coveralls.yml')
            ->spew("repo_token: $ENV{CIPH_COVERALLS_TOKEN}\n");
    }

    $c = 'codecovbash'  if $c eq 'codecov';
    $c = 'SonarGeneric' if $c eq 'sonarqube';

    $self->_with_brewed_perl_perl5lib(
        $self->runtime_perl,
        sub {
            $self->_system(
                $self->_perl_local_script( $self->runtime_perl, 'cover' ),
                '-report',    $c,
                '-outputdir', $self->coverage_dir,
                $self->coverage_dir->child('cover_db'),
            );
        },
    );

    return 0;
}

1;
