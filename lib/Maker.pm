package Maker;

use v5.26;
use strict;
use warnings;
use namespace::autoclean;
use autodie qw( :all );
use feature 'postderef', 'signatures';
use warnings 'FATAL' => 'all';

use File::pushd qw( pushd );
use FindBin qw( $Bin );
use IPC::Run3;
use List::AllUtils qw( first uniq );
use MetaCPAN::Client;
use Path::Tiny qw( path tempdir );
use Path::Tiny::Rule;
use Specio::Library::Builtins;
use Specio::Library::Path::Tiny;

use Moose;
## no critic (TestingAndDebugging::ProhibitNoWarnings)
no warnings 'experimental::postderef', 'experimental::signatures';
## use critic

with 'MooseX::Getopt::Dashes';

has push => (
    is      => 'ro',
    isa     => t('Bool'),
    default => 0,
);

has versions => (
    is      => 'ro',
    isa     => t( 'ArrayRef', of => t('Str') ),
    default => sub { [] },
);

has force_tools => (
    is      => 'ro',
    isa     => t('Bool'),
    default => 0,
);

has force_runtime => (
    is      => 'ro',
    isa     => t('Bool'),
    default => 0,
);

has _perls => (
    is      => 'ro',
    isa     => t( 'ArrayRef', of => t( 'HashRef', of => t('Str') ) ),
    isa     => 'ArrayRef[HashRef[Str]]',
    lazy    => 1,
    builder => '_build_perls',
);

has _latest_stable_perl => (
    is      => 'ro',
    isa     => t('Str'),
    lazy    => 1,
    default => sub ($self) {
        my $l = first { !( $_->{minor} % 2 ) } reverse $self->_perls->@*;
        return $l->{version};
    },
);

has _tools_dir => (
    is      => 'ro',
    isa     => t('Dir'),
    default => sub { path( $Bin, 'tools' )->absolute },
);

has _docker_tmp_dir => (
    is      => 'ro',
    isa     => t('Path'),
    default => sub { path( $Bin, 'docker-tmp' )->absolute },
);

# I wanted to use alpine but there's a serious bug with some Perls when
# compiled against musl libc. See
# https://github.com/plicease/Class-Inspector/issues/5 for
# details. Fortunately, Ubuntu's base images are now quite small (40-50mb).
my $TagRoot      = 'houseabsolute/ci-perl-helpers-ubuntu';
my $BaseImageTag = 'tools-perl';
my $BaseImage    = join q{:}, $TagRoot, $BaseImageTag;

my $M = MetaCPAN::Client->new;

sub run ($self) {
    $self->_create_tools_perl_image;
    $self->_create_runtime_perl_images;
    $self->_create_blead_perl_images;
    return 0;
}

sub _create_tools_perl_image ($self) {
    $self->_run_docker_build(
        $self->_tools_perl_dockerfile,
        [$BaseImageTag],
        $self->force_tools,
    );
}

sub _tools_perl_dockerfile ($self) {
    return sprintf( <<'EOF', $self->_latest_stable_perl );
FROM ubuntu:bionic

RUN apt-get --yes update && \
    apt-get --yes --no-install-recommends install \
        # For spelling tests
        aspell \
        aspell-en \
        ca-certificates \
        # Note that having curl over wget is important. When wget is installed
        # cpm will use that and then get weird 404 errors when making requests
        # to various metacpan URIs.
        curl \
        gcc \
        git \
        g++ \
        # Just added to make shelling in more pleasant.
        less \
        libc6-dev \
        # For XML-Parser which is a transitive dep of TAP::Harness::JUnit.
        libexpat-dev \
        # Same as less.
        libreadline7 \
        libssl1.1 \
        libssl-dev \
        make \
        patch \
        perl \
        # Needed in Azure CI where we don't run as root.
        # This is handy for debugging path issues.
        tree \
        zlib1g \
        zlib1g-dev

RUN mkdir ~/bin && \
    curl -fsSL --compressed https://git.io/cpm > /usr/local/bin/cpm && \
    chmod 0755 /usr/local/bin/cpm

RUN curl -L https://install.perlbrew.pl | sh && \
        mv /root/perl5 /usr/local/perl5

ENV PERLBREW_ROOT=/usr/local/perl5/perlbrew

ENV PATH=/usr/local/perl5/perlbrew/bin:$PATH

RUN perlbrew install --verbose --notest --noman -j $(nproc) --as tools-perl %s && \
    perlbrew clean

# We do this separately so we don't have to re-install everything when the
# tools code changes but the prereqs don't.
COPY ./tools/cpanfile /usr/local/ci-perl-helpers-tools/cpanfile

RUN perlbrew exec --with tools-perl \
        /usr/local/bin/cpm install \
            --global \
            --show-build-log-on-failure \
            --verbose \
            --workers 16 \
            --feature docker \
            --feature tools-perl \
            --cpanfile /usr/local/ci-perl-helpers-tools/cpanfile \
    && rm -fr /root/.perl-cpm

LABEL maintainer="Dave Rolsky <autarch@urth.org>"
EOF
}

sub _create_runtime_perl_images ($self) {
    my %images = $self->_images();
    for my $name (
        sort {
                   $images{$a}{minor} <=> $images{$b}{minor}
                || $images{$a}{thread} <=> $images{$b}{thread}
        } keys %images
    ) {
        my $content = $self->_released_perl_template( $images{$name} );

        $self->_run_docker_build(
            $content,
            $images{$name}{tags},
            $self->force_runtime,
        );
    }
}

sub _create_blead_perl_images ($self) {
    my $content = sprintf(
        <<'EOF', $BaseImage, $self->_runtime_tools_commands('blead') );
FROM %s

# It would make sense to put this in the root image but then every time a
# script changes we have to rebuild every Perl.
COPY ./tools /usr/local/ci-perl-helpers-tools

%s

# We'll need to download and install a new blead at CI time, so this directory
# needs to be owned by the user Azure Pipelines uses for runtime operations.
RUN chown -R 1001:1001 /usr/local/perl5

LABEL maintainer="Dave Rolsky <autarch@urth.org>"
EOF

    $self->_run_docker_build(
        $content,
        [ 'blead', 'blead-thread' ],
        $self->force_runtime,
    );
}

sub _run_docker_build ( $self, $content, $tags, $force_rebuild ) {
    my $tempdir = tempdir();
    my $df      = $tempdir->child( 'Dockerfile.' . $tags->[0] );
    $df->spew($content);

    say "Building $tags->[0] image" or die $!;
    print "\n$content" or die $!;

    my @full_tags = map { $TagRoot . ':' . $_ } $tags->@*;

    _system(
        'docker',
        'build',
        ( $force_rebuild ? '--no-cache' : () ),
        '--file', $df,
        ( map { ( '--tag', $_ ) } @full_tags ),
        q{.},
    );
    $self->_push(@full_tags);
}

sub _images ($self) {
    my %images;
    for my $perl ( $self->_perls->@* ) {
        next
            if $self->versions->@* && !grep { $perl->{version} eq $_ }
            $self->versions->@*;

        my $name = $perl->{minor} % 2 ? 'dev' : $perl->{version};
        for my $thread ( 0, 1 ) {
            my @tags = ($name);
            push @tags, $perl->{version} =~ s/\.\d+$//r
                unless $name eq 'dev';

            if ($thread) {
                $name .= '-thread';
                $_    .= '-thread' for @tags;
            }

            $images{$name} = {
                $perl->%*,
                thread => $thread,
                tags   => \@tags,
            };
        }
    }

    return %images;
}

sub _build_perls ($self) {
    my $releases = $M->release( { distribution => 'perl' } );
    die 'No releases for perl?' unless $releases->total;

    my %perls;
    while ( my $r = $releases->next ) {
        next unless $r->name =~ /^perl-5/;
        next if $r->name    =~ /RC/;
        next if $r->version =~ /^v/;
        my ( $minor, $patch ) = $r->version =~ /5\.(0\d\d)(\d\d\d)/
            or next;

        $_ += 0 for $minor, $patch;
        push $perls{$minor}->@*, "5.$minor.$patch";
    }

    my @lasts;
    for my $minor ( sort { $a <=> $b } keys %perls ) {
        my @v = sort $perls{$minor}->@*;
        push @lasts, {
            minor   => $minor,
            version => $v[-1],
        };
    }

    my @last_dev;
    if ( $lasts[-1]{minor} % 2 ) {
        @last_dev = $lasts[-1];
    }

    return [ ( grep { !( $_->{minor} % 2 ) } @lasts ), @last_dev ];
}

sub _released_perl_template ( $self, $image ) {
    my $as = 'perl-' . $image->{version};
    $as .= '-thread' if $image->{thread};

    my $thread_arg = $image->{thread} ? '--thread' : q{};
    my $file       = sprintf(
        <<'EOF', $BaseImage, $thread_arg, $image->{version}, $self->_runtime_tools_commands( $image->{version} ) );
FROM %s

COPY ./eg/patchperl /usr/local/perl5/perlbrew/bin/patchperl

RUN perlbrew install --verbose %s --notest --noman -j $(nproc) --as runtime-perl %s && \
    perlbrew clean

# perlbrew exits 0 when an install fails and --verbose is passed - see
# https://rt.cpan.org/Ticket/Display.html?id=131012
RUN perl -e 'my $output = `perlbrew -q exec --with runtime-perl perl -e "print q{ok}"`; die if $?; die qq{no runtime-perl was installed!\n} unless $output eq q{ok}'

%s

LABEL maintainer="Dave Rolsky <autarch@urth.org>"
EOF
}

sub _runtime_tools_commands {
    my $self = shift;
    my $perl = shift;

    my $is_58 = $perl =~ /^5\.8/;

    my $cpm = <<'EOF';
perlbrew exec --with runtime-perl \
        /usr/local/bin/cpm install \
            --global \
            --show-build-log-on-failure \
            --verbose \
            --workers 16 \
            --feature runtime \
            --cpanfile /usr/local/ci-perl-helpers-tools/cpanfile \
EOF

    # The Devel::Cover::Report::SonarGeneric distro needs 5.10+
    if ( !$is_58 ) {
        $cpm .= <<'EOF';
            --feature coverage \
            --feature 'coverage-codecov' \
            --feature 'coverage-clover' \
            --feature 'coverage-coveralls' \
            --feature 'coverage-html' \
            --feature 'coverage-kritika' \
            --feature 'coverage-sonarqube' \
EOF
    }

    $cpm .= <<'EOF';
    && \
    rm -fr /root/.perl-cpm
EOF

    if ( !$is_58 ) {
        $cpm = <<'EOF' . $cpm;
perlbrew exec --with runtime-perl \
        /usr/local/bin/cpm install \
            --global \
            --show-build-log-on-failure \
            --verbose \
            --workers 16 \
            # Required for Devel-Cover-Report-SonarGeneric - see
            # https://github.com/tomk3003/devel-cover-report-sonargeneric/issues/1
            ExtUtils::MakeMaker \
            # Required for Sub::Retry because it has a Build.PL that attempts
            # to read META.json files using CPAN::Meta, which in turn requires
            # JSON::PP 2.273000. This is core in newer Perls, but some older
            # Perls have an earlier version, which leads to issues. Several
            # coverage report distros need Sub::Retry. We need to install this
            # before we install from our cpanfile to guarantee that it's
            # available.
            JSON::PP \
    && \
EOF
    }

    return sprintf( <<'EOF', $cpm );
RUN %s

# It would make sense to put this in the root image but then every time a
# script changes we have to rebuild every Perl.
COPY ./tools /usr/local/ci-perl-helpers-tools

RUN set -e; \
    for tool in /usr/local/ci-perl-helpers-tools/bin/*.pl; do \
        perlbrew exec --with tools-perl \
            perl -c $tool; \
    done

ENV TZ=UTC

EOF
}

sub _push ( $self, @tags ) {
    return unless $self->push;
    say "Pushing tags: @tags" or die $!;
    _system( 'docker', 'push', $_ ) for @tags;
}

sub _run3 (@c) {
    print "\n"   or die $!;
    say ">>> @c" or die $!;
    print "\n"   or die $!;

    my ( $stdout, $stderr );
    run3(
        \@c,
        \undef,
        \$stdout,
        \$stderr,
    );

    die $stderr if $stderr;
    die "@c exited non-0" if $?;

    return $stdout;
}

sub _system (@c) {
    print "\n"   or die $!;
    say ">>> @c" or die $!;
    print "\n"   or die $!;
    system(@c);
}

__PACKAGE__->meta->make_immutable;

1;
