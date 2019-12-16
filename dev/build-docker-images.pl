#!/usr/bin/env perl

{
    package Builder;

    use v5.30.1;
    use strict;
    use warnings;
    use feature 'postderef', 'signatures';
    use warnings 'FATAL' => 'all';
    use autodie qw( :all );
    use namespace::autoclean;

    use FindBin qw( $Bin );
    use Path::Tiny qw( path tempdir );
    use Specio::Library::Builtins;
    use Specio::Library::Path::Tiny;
    use Specio::Library::String;

    use Moose;
    ## no critic (TestingAndDebugging::ProhibitNoWarnings)
    no warnings 'experimental::postderef', 'experimental::signatures';
    ## use critic

    use lib "$Bin/../deploy/lib";

    with 'MooseX::Getopt', 'R::Tagger';

    has perl => (
        is            => 'ro',
        isa           => t('NonEmptyStr'),
        required      => 1,
        documentation => 'Enable debugging output for the test run',
    );

    has push => (
        is            => 'ro',
        isa           => t('Bool'),
        default       => 0,
        documentation => 'Push the created images',
    );

    has threads => (
        is            => 'ro',
        isa           => t('Bool'),
        default       => 0,
        documentation => 'Write the runtime-perl with threads enabled.',
    );

    has _context => (
        is      => 'ro',
        isa     => t('Dir'),
        lazy    => 1,
        default => sub { path($Bin)->parent },
    );

    sub run {
        my $self = shift;

        my $tempdir = tempdir();
        $self->_build_tools_perl_image($tempdir);
        $self->_build_runtime_perl_image($tempdir);

        return 0;
    }

    sub _build_tools_perl_image {
        my $self    = shift;
        my $tempdir = shift;

        my $dockerfile = $tempdir->child('Dockerfile.tools-perl');
        _system(
            $^X,
            path( $Bin, qw( .. deploy bin write-tools-perl-dockerfile.pl ) ),
            '--filename', $dockerfile,
        );

        $self->_docker_stuff( $dockerfile, $self->_base_image );

        return undef;
    }

    sub _build_runtime_perl_image {
        my $self    = shift;
        my $tempdir = shift;

        my $dockerfile = $tempdir->child('Dockerfile.tools-perl');
        _system(
            $^X,
            path(
                $Bin, qw( .. deploy bin write-runtime-perl-dockerfile.pl )
            ),
            '--perl',     $self->perl,
            '--filename', $dockerfile,
            ( $self->threads ? '--threads' : '--no-threads' ),
        );

        my @perls = $self->perl;
        push @perls, $self->perl =~ s/\.\d+$//r;
        my @tags;
        for my $perl (@perls) {
            for my $iv ( grep { !/^v\d+\.\d+\.\d+$/ }
                $self->image_versions->@* ) {
                push @tags, sprintf(
                    '%s:%s-%s',
                    $self->_tag_root,
                    $perl,
                    $iv,
                );
            }
        }

        $self->_docker_stuff( $dockerfile, @tags );

        return undef;
    }

    sub _docker_stuff {
        my $self       = shift;
        my $dockerfile = shift;
        my @tags       = @_;

        _system(
            'docker',
            'build',
            '--file', $dockerfile,
            '--tag',  $_,
            $self->_context,
        ) for @tags;

        if ( $self->push ) {
            _system(
                'docker',
                'push',
                $_,
            ) for @tags;
        }

        return undef;
    }

    sub _system {
        say "@_";
        system(@_);
    }
}

exit Builder->new_with_options->run;
