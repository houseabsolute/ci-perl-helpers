#!/usr/bin/env perl

use strict;
use warnings;

{
    package Tester;

    use namespace::autoclean;
    use autodie qw( :all );

    use FindBin qw( $Bin );
    use File::Copy::Recursive qw( rcopy );
    use IPC::Run3 qw( run3 );
    use Path::Tiny qw( path tempdir );
    use Specio::Library::Builtins;
    use Specio::Library::Path::Tiny;
    use Specio::Library::String;

    use Moo;
    use MooX::Options;

    option debug => (
        is      => 'ro',
        isa     => t('Bool'),
        default => 1,
        doc     => 'Enable debugging output for the test run',
    );

    # https://github.com/geofffranks/test-mockmodule.git - Module::Build
    #
    # https://github.com/dotandimet/Mojo-Feed.git - Minilla
    option repo => (
        is      => 'ro',
        isa     => t('NonEmptyStr'),
        format  => 's',
        default => 'https://github.com/houseabsolute/DateTime.pm.git',
        doc => 'The repo to clone and test - defaults to using DateTime.pm',
    );

    option branch => (
        is      => 'ro',
        isa     => t('NonEmptyStr'),
        format  => 's',
        default => 'master',
        doc     => 'The branch of the repo to use. Defaults to master.',
    );

    option code => (
        is     => 'ro',
        isa    => t('NonEmptyStr'),
        format => 's',
        doc =>
            'A local directory containing the code to use for testing. This should be a git checkout of a Perl project.',
    );

    option coverage => (
        is     => 'ro',
        isa    => t('NonEmptyStr'),
        format => 's',
        doc    => 'The value to set for CIPH_COVERAGE, if any.',
    );

    option xt => (
        is      => 'ro',
        isa     => t('Bool'),
        default => 0,
        doc     => 'Set CIPH_TEST_XT to a true value.',
    );

    option partitions => (
        is     => 'ro',
        isa    => t('NonEmptyStr'),
        format => 's',
        doc => q{Test partition settings in the form $x:$y, where $x is the}
            . q{ current partition and $y is the total number of partitions.},
    );

    option perl => (
        is       => 'ro',
        isa      => t('NonEmptyStr'),
        format   => 's',
        required => 1,
        doc      => 'The perl version to use for testing',
    );

    has root => (
        is      => 'ro',
        isa     => t('Dir'),
        default => sub { path( $Bin, '..' )->absolute },
    );

    sub run {
        my $self = shift;

        $self->_build_images;

        my $tempdir = tempdir();

        # XXX - This will be owned by the current user but we will run as user
        # 1001 in the Docker container. It'd be nicer to just chown it but
        # that'd require root privs.
        $tempdir->chmod(0777);

        if ( $self->code ) {

            # Path::Tiny->remove_tree seems to not remove .git dirs for some
            # reason.
            system("rm -fr $Bin/tmp/project");
            rcopy( $self->code, "$Bin/tmp/project" );
        }

        my @env;
        push @env, ( '--env', 'CIPH_COVERAGE=' . $self->coverage )
            if $self->coverage;
        push @env, ( '--env', 'CIPH_TEST_XT=1' )
            if $self->xt;
        push @env, ( '--env', 'CIPH_DEBUG=1' )
            if $self->debug;

        print "\n** BUILD **\n\n";
        system(
            'docker', 'run',
            '--interactive',
            '--tty',
            @env,
            '--user', 1001,
            '--volume',
            ( join q{:}, $tempdir->absolute, '/__w/artifacts' ),
            'ci-perl-helpers-local-build',
            '/bin/bash',
            '-c',
            $self->_bash_build_command,
        );

        print "\n** TEST **\n\n";
        system(
            'docker', 'run',
            '--interactive',
            '--tty',
            @env,
            '--user', 1001,
            '--volume',
            ( join q{:}, $tempdir->absolute, '/__w/artifacts' ),
            'ci-perl-helpers-local-test',
            '/bin/bash',
            '-c',
            $self->_bash_test_command,
        );
    }

    sub _build_images {
        my $self = shift;

        for my $type (qw( build test )) {
            my $tempdir = tempdir();
            my $df      = $tempdir->child( 'Dockerfile.' . $type );
            $df->spew( $self->_dockerfile($type) );

            my $tag = 'ci-perl-helpers-local-' . $type;
            system(
                'docker', 'build',
                '--no-cache',
                '-f', $df,
                '-t', $tag,
                $self->root,
            );
        }

        return undef;
    }

    sub _bash_build_command {
        my $self = shift;

        return <<'EOF';
set -e
set -x
export CI_ARTIFACT_STAGING_DIRECTORY=/__w/artifacts
export CI_SOURCE_DIRECTORY=/__w/project
export CI_WORKSPACE_DIRECTORY=/__w
pushd $CI_WORKSPACE_DIRECTORY/project
( /usr/local/ci-perl-helpers-tools/bin/with-perl tools-perl show-env.pl && \
      /usr/local/ci-perl-helpers-tools/bin/with-perl tools-perl pre-build.pl && \
      /usr/local/ci-perl-helpers-tools/bin/with-perl tools-perl install-build-deps.pl && \
      /usr/local/ci-perl-helpers-tools/bin/with-perl tools-perl build-dist.pl ) || \
    bash
EOF
    }

    sub _bash_test_command {
        my $self = shift;

        my $this_partition = q{};
        my $partitions     = q{};
        if ( $self->partitions ) {
            ( $this_partition, my $total_partitions ) = split /:/,
                $self->partitions;
            $partitions = join ',', 1 .. $total_partitions;
        }

        return
            sprintf(
            <<'EOF', $this_partition, $this_partition, $partitions, $this_partition, $self->perl );
set -e
set -x
export CI_ARTIFACT_STAGING_DIRECTORY=/__w/artifacts
export CI_SOURCE_DIRECTORY=/__w/project
export CI_WORKSPACE_DIRECTORY=/__w
pushd $CI_WORKSPACE_DIRECTORY
if [ -n "%d" ]; then
    # There is no default stringification for arrays, so we need to
    # make a string to use the all_partitions parameter.
    export CIPH_TOTAL_COVERAGE_PARTITIONS=$( \
        /usr/local/ci-perl-helpers-tools/bin/with-perl tools-perl print-total-partitions.pl \
            --this-partition "%d" \
            --partitions "%s" \
    )
    export CIPH_COVERAGE_PARTITION=%d
fi
( /usr/local/ci-perl-helpers-tools/bin/with-perl tools-perl show-env.pl && \
      /usr/local/ci-perl-helpers-tools/bin/with-perl tools-perl pre-test.pl --runtime-perl %s && \
      /usr/local/ci-perl-helpers-tools/bin/with-perl tools-perl build-cpanfile.pl && \
      /usr/local/ci-perl-helpers-tools/bin/with-perl tools-perl install-prereqs.pl && \
      /usr/local/ci-perl-helpers-tools/bin/with-perl tools-perl prep-for-tests.pl && \
      /usr/local/ci-perl-helpers-tools/bin/with-perl tools-perl install-dynamic-prereqs.pl && \
      /usr/local/ci-perl-helpers-tools/bin/with-perl tools-perl run-tests.pl ) || \
    bash
EOF
    }

    sub _dockerfile {
        my $self = shift;
        my $from = shift;

        my $from_tag  = $from eq 'build' ? 'tools-perl' : $self->perl;
        my $with_perl = $from eq 'build' ? 'tools-perl' : 'runtime-perl';

        my $cpm = $from eq 'build'
            ? <<'EOF'
perlbrew exec --with tools-perl \
        /usr/local/bin/cpm install \
            --global \
            --show-build-log-on-failure \
            --verbose \
            --workers 16 \
            --feature docker \
            --feature tools-perl \
            --cpanfile /usr/local/ci-perl-helpers-tools/cpanfile
EOF
            : <<'EOF';
perlbrew exec --with runtime-perl \
        /usr/local/bin/cpm install \
            --global \
            --show-build-log-on-failure \
            --verbose \
            --workers 16 \
            --feature coverage \
            --feature 'coverage-codecov' \
            --feature 'coverage-clover' \
            --feature 'coverage-coveralls' \
            --feature 'coverage-html' \
            --feature 'coverage-kritika' \
            --feature 'coverage-sonarqube' \
            --feature runtime \
            --cpanfile /usr/local/ci-perl-helpers-tools/cpanfile
EOF

        my $distro;
        if ( $self->code ) {
            $distro = 'COPY ./dev/tmp/project /__w/project';
        }
        else {
            $distro = sprintf(
                'RUN git clone %s /__w/project && cd /__w/project && git checkout %s',
                $self->repo, $self->branch
            );
        }

        return sprintf( <<'EOF', $from_tag, $distro, $cpm );
FROM houseabsolute/ci-perl-helpers-ubuntu:%s

RUN useradd -m -u 1001 vsts_azpcontainer

RUN mkdir /__w

COPY ./tools/cpanfile /usr/local/ci-perl-helpers-tools/cpanfile

%s

RUN chown -R 1001:1001 /__w

RUN %s

COPY ./tools /usr/local/ci-perl-helpers-tools

RUN set -e; \
    for tool in /usr/local/ci-perl-helpers-tools/bin/*.pl; do \
        perlbrew exec --with tools-perl \
            perl -c $tool; \
    done

ENV TZ=UTC
EOF
    }
}

Tester->new_with_options->run;
