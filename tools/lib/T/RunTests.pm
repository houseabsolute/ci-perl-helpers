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

    my $tempdir = tempdir();
    my $archive = $tempdir->child('prove.tar.gz');
    my $exit;
    $self->_with_brewed_perl_perl5lib(
        $self->runtime_perl,
        sub {
            $exit = $self->_system_no_die(
                $self->_brewed_perl( $self->runtime_perl ),
                'prove',
                '--archive', $archive,
                '--blib',
                '--jobs', 10,
                '--merge',
                '--recurse',
                '--verbose',
                @{ $self->test_dirs },
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

    $self->_tap2junit($archive);

    $self->_maybe_run_coverage_report;

    return 0;
}

sub _tap2junit {
    my $self    = shift;
    my $archive = shift;

    my $dir = $self->_pushd( $archive->parent );

    $self->_system(
        'tar',
        '--extract',
        '--gzip',
        '--verbose',
        '--file', $self->_posix_path($archive),
    );

    my @t_files = Path::Tiny::Rule->new->file->name(qr/\.t$/)->all('.');

    $self->_with_brewed_perl_perl5lib(
        $self->tools_perl,
        sub {
            $self->_system(
                $self->_perl_local_script( $self->tools_perl, 'tap2junit' ),
                @t_files,
            );
        },
    );

    my $j = $self->workspace_root->child('junit');
    $self->_debug("Making $j for junit files");
    $j->mkpath( 0, 0755 );

    for my $xml ( Path::Tiny::Rule->new->file->name(qr/\.xml$/)->all('.') ) {
        my $to = $j->child($xml);
        $to->parent->mkpath( 0, 0755 );
        $self->_debug("Copy $xml to $to");
        $xml->copy($to);
    }

    return undef;
}

sub _maybe_run_coverage_report {
    my $self = shift;

    my $c = $self->coverage
        or return undef;

    if ( $c eq 'coveralls' ) {
        path('.coveralls.yml')->spew("repo_token: $ENV{CIPH_COVERALLS_TOKEN}\n");
    }

    $c = 'codecovbash' if $c eq 'codecov';
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
