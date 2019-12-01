package D::WriteRuntimePerlDockerfile;

use v5.30.1;
use strict;
use warnings;
use feature 'postderef', 'signatures';
use warnings 'FATAL' => 'all';
use autodie qw( :all );
use namespace::autoclean;

use Specio::Library::Builtins;

use Moose;
## no critic (TestingAndDebugging::ProhibitNoWarnings)
no warnings 'experimental::postderef', 'experimental::signatures';
## use critic

has threads => (
    is            => 'ro',
    isa           => t('Bool'),
    required      => 1,
    documentation => 'Write the runtime-perl with threads enabled.',
);

with 'R::DockerfileWriter', 'R::Tagger';

sub run ($self) {
    $self->_write_dockerfile;
    return 0;
}

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _content ($self) {
    return $self->_blead_content
        if $self->perl eq 'blead';

    my $thread_arg = $self->threads ? '--threads' : q{};

    my @p = (
        $self->_base_image,
        $thread_arg,
        $self->perl,
        $self->_runtime_tools_commands,
    );

    return sprintf( <<'EOF', @p );
FROM %s

RUN perlbrew install --verbose %s --notest --noman -j $(nproc) --as runtime-perl %s && \
    perlbrew clean

# perlbrew exits 0 when an install fails and --verbose is passed - see
# https://rt.cpan.org/Ticket/Display.html?id=131012
RUN perl -e 'my $output = `perlbrew -q exec --with runtime-perl perl -e "print q{ok}"`; die if $?; die qq{no runtime-perl was installed!\n} unless $output eq q{ok}'

%s

LABEL maintainer="Dave Rolsky <autarch@urth.org>"
EOF
}
## use critic

sub _runtime_tools_commands ($self) {
    my $cpm = $self->_cpm_commands;

    return sprintf( <<'EOF', $cpm );
%s

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

sub _cpm_commands ($self) {
    return q{} if $self->perl eq 'blead';

    my $is_58 = $self->perl =~ /^5\.8/;

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

    return 'RUN ' . $cpm;
}

sub _blead_content ($self) {
    return
        sprintf(
        <<'EOF', $self->_base_image, $self->_runtime_tools_commands );
FROM %s

%s

# It would make sense to put this in the root image but then every time a
# script changes we have to rebuild every Perl.
COPY ./tools /usr/local/ci-perl-helpers-tools

# We'll need to download and install a new blead at CI time, so this directory
# needs to be owned by the user Azure Pipelines uses for runtime operations.
RUN chown -R 1001:1001 /usr/local/perl5

LABEL maintainer="Dave Rolsky <autarch@urth.org>"
EOF
}

__PACKAGE__->meta->make_immutable;

1;
