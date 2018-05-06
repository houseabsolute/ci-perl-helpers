package T::CPANInstall;

use strict;
use warnings FATAL => 'all';
use autodie qw( :all );

use local::lib '--deactivate-all';

use Getopt::Long qw( :config pass_through );
use Path::Tiny qw( path );
use Specio::Library::Path::Tiny;

use Moo;
use MooX::StrictConstructor;

with 'R::HelperScript';

has cpm => (
    is      => 'ro',
    isa     => t('File'),
    default => sub {
        $^O eq 'linux'
            ? path(qw( /usr local bin cpm ))->absolute
            : $_[0]->workspace_root->child(qw( bin cpm ));
    },
);

sub run {
    my $self = shift;

    my $perl;
    GetOptions( 'perl:s' => \$perl );

    # We might run this script with one perl and want to run cpm with another,
    # so it's best to make sure this is unset before invoking local::lib.
    local $ENV{PERL5LIB} = q{};

    local::lib->new( no_create => 1, quiet => 1 )
        ->activate( $self->local_lib_root->child($perl) )->setup_local_lib;

    $self->_system(
        $self->_brewed_perl($perl),
        'perl',
        $self->cpm,
        'install',

        # Despite saying global this will end up installing into the
        # local::lib paths, not the installed Perl's paths.
        '--global',
        ( $self->debug ? '--verbose' : '--show-progress' ),

        # cpm can only use one worker on Windows
        ( $^O eq 'MSWin32' ? () : ( '--workers', 16 ) ),
        '--no-prebuilt',
        '--show-build-log-on-failure',
        @ARGV,
    );

    return 0;
}

1;
