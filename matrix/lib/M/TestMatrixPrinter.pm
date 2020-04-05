# This code should be runnable with the system perl installed on the latest
# Ubuntu VM on Azure. We want to run this without installing a new Perl or any
# modules, for maximum speed, since this script blocks kicking off parallel
# testing.
package M::TestMatrixPrinter;

use v5.26.1;
use strict;
use warnings FATAL => 'all';
use autodie;

use Encode qw( decode );
use Getopt::Long;
use HTTP::Tiny;
use JSON::PP qw( decode_json encode_json );
use Time::Piece;

my %OS = map { $_ => 1 } qw( Linux macOS Windows );

sub new {
    my $class = shift;

    my %opts = ( debug => $ENV{CIPH_DEBUG} );
    my $perls;
    my $from_perl;
    my $to_perl;
    my $allow_failure;
    my $coverage_perl;
    GetOptions(
        'os:s'                  => \$opts{os},
        'berrybrew-tag:s'       => \$opts{berrybrew_tag},
        'perls:s'               => \$perls,
        'from-perl:s'           => \$from_perl,
        'to-perl:s'             => \$to_perl,
        'include-threads'       => \$opts{include_threads},
        'allow-failure:s'       => \$allow_failure,
        'test-xt'               => \$opts{test_xt},
        'image-version:s'       => \$opts{image_version},
        'coverage:s'            => \$opts{coverage},
        'coverage-perl:s'       => \$coverage_perl,
        'coverage-partitions:i' => \$opts{coverage_partitions},
        'pretty'                => \$opts{pretty},
    );

    my $self = bless \%opts, $class;

    my $ok = eval {
        unless ( $OS{ $opts{os} // q{} } ) {
            my $valid = join q{, }, sort { lc $a cmp lc $b } keys %OS;
            die "You must provide a valid --os ($valid) flag.";
        }

        if ( $opts{os} eq 'Windows' ) {
            unless ( ( $opts{berrybrew_tag} // q{} ) =~ /^v\d+\.\d+$/a ) {
                die
                    'You must provide a valid --berrybrew-tag when the OS is set to Windows.';
            }
            if ( $opts{include_threads} ) {
                die
                    'You cannot pass --include-threads when generating a matrix for Windows.';
            }
        }

        if ( $perls && $from_perl ) {
            die
                qq{You cannot pass both `perls` and `from_perl` parameters to the $opts{os} stage.};
        }
        elsif ( $perls && $to_perl ) {
            die
                qq{You cannot pass both `perls` and `to_perl` parameters to the $opts{os} stage.};
        }
        elsif ( !( $perls || $from_perl || $to_perl ) ) {
            die
                qq{Tried to generate the $opts{os} matrix but none of `perls`, `from_perl`, or `to_perl` were set.};
        }

        $self->_set_selected_perls( $perls, $from_perl, $to_perl );

        if ($allow_failure) {
            my @allow_failure
                = $self->_clean_perl_versions( split /,/, $allow_failure );
            if (@allow_failure) {
                $self->_validate_perls(@allow_failure);
                $self->{allow_failure} = \@allow_failure;
            }
        }

        if ($coverage_perl) {
            ($coverage_perl) = $self->_clean_perl_versions($coverage_perl);
            $self->_validate_perls($coverage_perl);
            $self->{coverage_perl}
                = $self->_latest_matching_perl($coverage_perl);
        }

        return 1;
    };
    unless ($ok) {
        _error($@);
        return undef;
    }

    return $self;
}

sub _set_selected_perls {
    my $self      = shift;
    my $perls     = shift;
    my $from_perl = shift;
    my $to_perl   = shift;

    if ($perls) {
        my @perls = $self->_clean_perl_versions( split /,/, $perls );
        $self->_validate_perls(@perls)
            or return undef;
        $self->{selected_perls}
            = [ map { $self->_latest_matching_perl($_) } @perls ];
        return undef;
    }

    $self->_selected_perls_from_range(
        $self->_clean_perl_versions( $from_perl, $to_perl ) );

    return undef;
}

sub _clean_perl_versions {
    my $self = shift;

    return map { $self->_clean_one_version($_) } @_;
}

sub _clean_one_version {
    my $self = shift;
    my $ver  = shift;

    return undef unless defined $ver;

    return $ver eq 'latest'
        ? $self->_perl_data->{latest_stable_version}{version}

        # Azure Pipelines seems to numify string parameters that look like
        # numbers so that "5.30" becomes "5.3". Fortunately, we're about
        # 50 years from 5.80, so we can safely assume that any version
        # less than "5.8" is one of those numified versions.
        : $ver =~ /^\d+\.(\d+)$/a && $1 < 8 ? $ver .= '0'
        :                                     $ver;
}

sub _latest_matching_perl {
    my $self   = shift;
    my $wanted = shift;

    # If the wanted perl is something like "5.30" we pick the latest patch
    # version of 5.30.
    my @matches = sort { $a->{version_numified} <=> $b->{version_numified} }
        grep { $_->{version} =~ /^\Q$wanted/ }
        values %{ $self->_perl_data->{perls} };
    return $matches[-1];
}

sub _selected_perls_from_range {
    my $self = shift;

    my ( $from_perl_num, $to_perl_num, $include_dev, $include_blead )
        = $self->_range_as_numbers(@_);

    my @perls;
    for my $perl ( sort { $a->{version_numified} <=> $b->{version_numified} }
        values %{ $self->_perl_data->{perls} } ) {

        unless ( $perl->{maturity} eq 'released' ) {
            $self->_debug(
                "Skipping $perl->{name} ($perl->{maturity}) because it is not marked as stable"
            );
            next;
        }
        unless ( $perl->{is_latest_in_minor} ) {
            $self->_debug(
                "Skipping $perl->{name} ($perl->{maturity}) because it is not the last of its minor release series"
            );
            next;
        }

        next
            unless $from_perl_num <= $perl->{version_numified}
            && $perl->{version_numified} <= $to_perl_num;
        push @perls, $perl;
    }

    if ( $self->{os} ne 'Windows' ) {
        if ($include_dev) {
            push @perls,
                {
                version          => 'dev',
                version_numified => 998,
                maturity         => 'developer',
                };
        }
        if ($include_blead) {
            push @perls,
                {
                version          => 'blead',
                version_numified => 999,
                maturity         => 'developer',
                };
        }
    }

    $self->{selected_perls} = \@perls;

    return undef;
}

sub _range_as_numbers {
    my $self      = shift;
    my $from_perl = shift;
    my $to_perl   = shift;

    my ( $from_perl_num, $to_perl_num, $include_dev, $include_blead );
    if ($from_perl) {
        $self->_validate_perls($from_perl)
            or return undef;

        # This ensures that if we have something like "5.24 ... 5.28" we include
        # both 5.24 and 5.28 in our range.
        $from_perl .= '.0'
            if $from_perl =~ /^\d+\.\d+$/a;
        $from_perl_num = $self->_numify($from_perl);
    }
    if ($to_perl) {
        $self->_validate_perls($to_perl)
            or return undef;

        if ( $to_perl eq 'dev' ) {
            $include_dev = 1;
            $to_perl = $self->_perl_data->{latest_stable_version}{version};
        }
        elsif ( $to_perl eq 'blead' ) {
            $include_dev   = 1;
            $include_blead = 1;
            $to_perl = $self->_perl_data->{latest_stable_version}{version};
        }

        $to_perl .= '.999'
            if $to_perl =~ /^\d+\.\d+$/a;
        $to_perl_num = $self->_numify($to_perl);
    }
    else {
        $include_dev   = 1;
        $include_blead = 1;
    }

    if ( $from_perl_num && $to_perl_num ) {
        unless ( $from_perl_num <= $to_perl_num ) {
            die
                "The from_perl parameter ($from_perl) is not less than or equal to the to_perl parameter ($to_perl)";
        }
    }

    $from_perl_num //= 5.008_009;
    $to_perl_num   //= 10**10;

    return ( $from_perl_num, $to_perl_num, $include_dev, $include_blead );
}

sub _numify {
    shift;
    my $version = shift;

    my ( $maj, $min, $patch ) = split /\./, $version;
    $patch //= 0;

    return sprintf( '%d.%03d%03d', $maj, $min, $patch );
}

sub _validate_perls {
    my $self  = shift;
    my @perls = @_;

    my $ok      = $self->_perl_data->{identifiers};
    my @invalid = grep { !$ok->{$_} } @perls
        or return 1;

    die "Arguments included one or more invalid Perl versions: @invalid";
}

sub _perl_data {
    my $self = shift;
    return $self->{perl_data} //= $self->_build_perl_data;
}

sub _build_perl_data {
    my $self = shift;

    my @raw;
    if ( $self->{os} eq 'Windows' ) {
        @raw = $self->_perl_data_from_berrybrew;
    }
    else {
        @raw = $self->_get_perls_from_metacpan;
    }

    my $repo_date = $self->_repo_date;

    my %identifiers;
    my %perls;
    my %minors;
    for my $perl (@raw) {
        if ( $perl->{version_numified} < 5.008 ) {
            $self->_debug(
                "Skipping $perl->{name} because $perl->{version_numified} < 5.008"
            );
            next;
        }

        if (   $perl->{version_numified} >= 5.008
            && $perl->{version_numified} < 5.008009 ) {
            $self->_debug(
                "Skipping perl $perl->{name} because we don't include 5.8.x except for 5.8.9"
            );
            next;
        }

        if (   $perl->{version_numified} >= 5.010
            && $perl->{version_numified} < 5.010001 ) {
            $self->_debug(
                "Skipping perl $perl->{name} because we don't include 5.10.x except for 5.10.1"
            );
            next;
        }

        if ( $perl->{name} =~ /-RC/ ) {
            $self->_debug("Skipping perl $perl->{name} because it is an RC");
            next;
        }

        my ( $full, $majmin, $min ) = $perl->{name} =~ /-((5\.(\d+))\.\d+)/a;
        unless ($full) {
            die "Could not figure out perl version from name: $perl->{name}";
        }

        # There are a whole bunch of -RCX releases that parse as the same
        # version as a real released version.
        if (   exists $perls{$full}
            && $perls{$full}{maturity} eq 'released'
            && $perl->{maturity} eq 'developer' ) {

            $self->_debug("Skipping perl $perl->{name} because it is an RC");
            next;
        }

        my $release_date
            = Time::Piece->strptime( $perl->{date}, '%Y-%m-%dT%H:%M:%S' );
        if ( $release_date >= $repo_date ) {
            $self->_debug(
                "Skipping perl $perl->{name} because it was released after this commit ($release_date > $repo_date)"
            );
            next;
        }

        $perl->{version} = $full;
        $perl->{minor}   = $min;

        push @{ $minors{$min} }, $perl;

        $perls{$full}         = $perl;
        $identifiers{$full}   = 1;
        $identifiers{$majmin} = 1;
    }

    for my $minor ( keys %minors ) {
        my @sorted
            = sort { $a->{version_numified} <=> $b->{version_numified} }
            @{ $minors{$minor} };
        $sorted[-1]{is_latest_in_minor} = 1;
    }

    if ( $self->{os} ne 'Windows' ) {
        $identifiers{dev}   = 1;
        $identifiers{blead} = 1;
    }

    my $latest_stable_version = (
        sort { $a->{version_numified} cmp $b->{version_numified} }
        grep { $_->{maturity} eq 'released' } values %perls
    )[-1];

    return {
        identifiers           => \%identifiers,
        perls                 => \%perls,
        latest_stable_version => $latest_stable_version,
    };
}

sub _get_perls_from_metacpan {
    my $ht = HTTP::Tiny->new;

    my %query = (
        size   => 5000,
        query  => { term => { distribution => 'perl' } },
        fields => [qw( date maturity name version version_numified )],
    );

    my $uri  = 'https://fastapi.metacpan.org/v1/release/_search';
    my $body = encode_json( \%query );
    my $resp = $ht->post(
        $uri, {
            headers => {
                'Accepts'      => 'application/json',
                'Content-Type' => 'application/json',
            },
            content => $body,
        },
    );
    unless ( $resp->{success} ) {
        my $msg
            = "Error POSTing to $uri with body: $body\nstatus = $resp->{status}\n";
        $msg .= "$resp->{content}\n" if $resp->{content};
        die $msg;
    }

    my $decoded = decode_json( $resp->{content} );
    unless ($decoded) {
        die "POST to $uri did not return any content";
    }

    unless ( $decoded
        && ref $decoded eq 'HASH'
        && $decoded->{hits}
        && ref $decoded->{hits} eq 'HASH' ) {

        die
            "POST to $uri did not return content with the expected data structure: $resp->{content}";
    }

    unless ( $decoded->{hits}{total} ) {
        die "POST to $uri did not return any hits for perl releases";
    }

    return map { $_->{fields} } @{ $decoded->{hits}{hits} };
}

sub _perl_data_from_berrybrew {
    my $self = shift;

    my $ht = HTTP::Tiny->new;

    my $uri
        = "https://raw.githubusercontent.com/stevieb9/berrybrew/$self->{berrybrew_tag}/data/perls.json";
    my $resp = $ht->get(
        $uri, {
            headers => {
                'Accepts' => 'application/json',
            },
        },
    );
    unless ( $resp->{success} ) {
        die "Error GETting $uri";
    }

    # For some reason when we get this file with HTTP::Tiny it has a BOM at
    # the start.
    my $decoded = decode_json( $resp->{content} =~ s/^[^\[]+//r );
    unless ($decoded) {
        die "GET $uri did not return any content";
    }

    my %raw;
    for my $perl ( @{$decoded} ) {

        # If we have both 64- and 32-bit versions of a Perl, we just keep the
        # 64-bit version.
        next
            if exists $raw{ $perl->{ver} }
            && $raw{ $perl->{ver} }{berrybrew_version} =~ /_64$/;

        $raw{ $perl->{ver} } = {

            # We don't really care about the date for Windows.
            date              => '1970-01-01T00:00:00',
            version           => $perl->{ver},
            name              => q{-} . $perl->{ver},
            version_numified  => $self->_numify( $perl->{ver} ),
            maturity          => 'released',
            berrybrew_version => $perl->{name},
        };
    }

    return values %raw;
}

sub _repo_date {
    my $cmd = q{git log --pretty='%aI' -1};
    ## no critic (InputOutput::ProhibitBacktickOperators )
    my $output = `$cmd`;
    if ($?) {
        my $exit = $? << 8;
        die "Error running $cmd - got exit code of $exit\n";
    }
    chomp $output;
    $output =~ s/([\-\+]\d\d):(\d\d)$/$1$2/a;
    return Time::Piece->strptime( $output, '%Y-%m-%dT%H:%M:%S%z' );
}

sub run {
    my $self = shift;

    my %matrix = (
        $self->_base_jobs,
        $self->_coverage_jobs,
    );

    my $j = JSON::PP->new->canonical;
    $j->pretty if $self->{pretty};

    say $j->encode( \%matrix )
        or die $!;

    return 0;
}

sub _base_jobs {
    my $self = shift;

    my %matrix;
    for my $perl ( @{ $self->{selected_perls} } ) {
        %matrix = (
            %matrix,
            $self->_base_job( $perl, 0 ),
            ( $self->{include_threads} ? $self->_base_job( $perl, 1 ) : () ),
        );
    }

    return %matrix;
}

sub _coverage_jobs {
    my $self = shift;

    return unless $self->{coverage};

    my $perl = $self->{coverage_perl}
        // $self->_perl_data->{latest_stable_version};
    my $key = $perl->{version} =~ s/\./_/gr;
    $key .= '_coverage';

    my $report = $self->{coverage} eq 'true' ? 'html' : $self->{coverage};

    my ( undef, $job ) = $self->_base_job($perl);
    $job->{test_xt} = 0;

    unless ( $self->{coverage_partitions}
        && $self->{coverage_partitions} > 1 ) {
        $job->{coverage} = $report;
        $job->{title} .= ' with coverage';

        return ( $key => $job );
    }

    my %matrix;
    for my $part ( 1 .. $self->{coverage_partitions} ) {
        my $new_key = $key . "_partition_$part";

        $job->{coverage}            = $report;
        $job->{coverage_partition}  = $part;
        $job->{coverage_partitions} = $self->{coverage_partitions};
        $job->{title}
            .= " with coverage (partition $part of $self->{coverage_partitions})";

        $matrix{$new_key} = $job;
    }

    return %matrix;
}

sub _base_job {
    my $self    = shift;
    my $perl    = shift;
    my $threads = shift;

    my $perl_param = $perl->{version};
    my $key        = $perl_param =~ s/\./_/gr;
    $key .= '_threads'
        if $threads;

    my $title = "$self->{os} $perl_param";
    $title .= ' threads' if $threads;

    my $test_xt = 0;
    if ( $self->{test_xt} && !$threads && $self->_is_max_stable_perl($perl) )
    {
        $title .= ' with extended tests';
        $test_xt = 1;
    }

    my $allow_failure
        = grep { $perl->{version} =~ /\Q$_/ } @{ $self->{allow_failure} };

    my %job = (
        perl          => $perl_param,
        threads       => ( $threads ? 1 : q{} ),
        title         => $title,
        allow_failure => ( $allow_failure ? 1 : 0 ),
        test_xt       => ( $test_xt ? 1 : 0 ),
        title         => $title,
        coverage      => q{},
    );

    if ( $self->{os} eq 'Linux' ) {
        $job{container} = sprintf(
            'houseabsolute/ci-perl-helpers-ubuntu:%s%s-%s',
            $perl_param,
            ( $threads ? '-threads' : q{} ),
            $self->{image_version},
        );
    }
    elsif ( $self->{os} eq 'macOS' ) {
        $job{latest_stable_perl}
            = $self->_perl_data->{latest_stable_version}{version};
    }
    elsif ( $self->{os} eq 'Windows' ) {
        $job{berrybrew_perl} = $perl->{berrybrew_version};
        $job{latest_stable_perl}
            = $self->_perl_data->{latest_stable_version}{berrybrew_version};
    }

    return ( $key => \%job );
}

sub _is_max_stable_perl {
    my $self = shift;
    my $perl = shift;

    $self->{max_stable_perl} //=
        ( grep { $_->{maturity} eq 'released' } @{ $self->{selected_perls} } )
        [-1]{version};

    return $perl->{version} eq $self->{max_stable_perl};
}

sub _debug {
    my $self = shift;

    return unless $self->{debug};

    warn @_, "\n" or die $!;
}

sub _error {
    my $msg = shift;

    print "##vso[task.logissue type=error;]$msg\n"
        or die $!;
    print "##vso[task.complete result=Failed;]\n"
        or die $!;

    return undef;
}

1;
