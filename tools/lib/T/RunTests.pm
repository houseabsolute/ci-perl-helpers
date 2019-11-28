package T::RunTests;

use strict;
use warnings FATAL => 'all';
use autodie qw( :all );

use Path::Tiny qw( path tempdir );
use Path::Tiny::Rule;
use Specio::Library::Path::Tiny;

use Moo;
use MooX::StrictConstructor;

has coverage_dir => (
    is      => 'ro',
    isa     => t('Path'),
    lazy    => 1,
    default => sub { $_[0]->workspace_root->child('coverage') },
);

with 'R::HelperScript';

sub run {
    my $self = shift;

    $self->_debug_step;

    my $dir = $self->_pushd( $self->extracted_dist_dir );

    local $ENV{HARNESS_PERL_SWITCHES} = $ENV{HARNESS_PERL_SWITCHES} || q{};
    if ( $self->coverage ) {
        $ENV{HARNESS_PERL_SWITCHES} .= q{:}
            if $ENV{HARNESS_PERL_SWITCHES};
        $ENV{HARNESS_PERL_SWITCHES}
            .= '-MDevel::Cover=-ignore,^x?t/,-blib,0,-dir,'
            . $self->coverage_dir;
        $self->_debug("HARNESS_PERL_SWITCHES=$ENV{HARNESS_PERL_SWITCHES}");
        $self->coverage_dir->mkpath( 0, 0755 );
    }

    my $exit;
    $self->_with_brewed_perl_perl5lib(
        $self->runtime_perl,
        sub {
            local $ENV{JUNIT_TEST_FILE}
                = $self->workspace_root->child('junit.xml');

            $exit = $self->_system_no_die(
                $self->_brewed_perl( $self->runtime_perl ),
                $self->_run_tests_command,
            );
        },
    );

    if ( $exit == -1 ) {
        die "Could not run prove at all: $!";
    }
    elsif ( $exit > 0 ) {
        my $code   = $? >> 8;
        my $signal = $? & 127;
        my $msg    = "Running tests with prove failed (exit code = $code";
        $msg .= ", signal = $signal" if $signal;
        $msg .= ').';
        if ( $self->allow_test_failures ) {
            print "##vso[task.logissue type=warning]$msg\n"
                or die $!;
        }
        else {
            die $msg;
        }
    }

    $self->_maybe_run_coverage_report;

    return 0;
}

sub _run_tests_command {
    my $self = shift;

    # Test2::Harness doesn't support Perl 5.8.
    if ( $self->runtime_is_5_8 ) {
        return (
            'prove',
            '--blib',
            '--jobs', 10,
            '--merge',
            '--recurse',
            '--verbose',
            @{ $self->test_paths },
        );
    }

    # We don't run yath with the --verbose flag because that produces a _huge_
    # amount of output. Just printing it to the console ends up taking enough
    # time to slow down the test run.
    return (
        'yath',
        'test',
        '--blib',
        '--jobs', 10,

        # This renderer will print to the console.
        '--renderer', 'Formatter',

        # This renderer will print to the JUNIT_TEST_FILE.
        '--renderer', 'JUnit',
        @{ $self->test_paths },
    );
}

sub _maybe_run_coverage_report {
    my $self = shift;

    my $c = $self->coverage
        or return undef;

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

    return undef;
}

1;
