use v5.30.1;
use strict;
use warnings 'FATAL' => 'all';
use feature 'postderef', 'signatures';
use autodie qw( :all );

use FindBin qw( $Bin );
use lib "$Bin/../../tools/lib", "$Bin/../../matrix/lib";

use Test2::V0;

use JSON::PP qw( encode_json );
use M::TestMatrixPrinter;

{
    no warnings 'redefine';
    ## no critic (Variables::ProtectPrivateVars)
    *M::TestMatrixPrinter::_error = sub { die $_[0] };
}

subtest 'constructor tests' => sub {
    my @constructor_tests = (
        [
            [],
            qr/\QYou must provide a valid --os (Linux, macOS, Windows) flag./,
            'constructor with no flags dies',
        ],
        [
            [qw( --os Windows )],
            qr/\QYou must provide a valid --berrybrew-tag when the OS is set to Windows./,
            '--os Windows requires a --berrybreq-tag flag',
        ],
        [
            [qw( --os Windows --berrybrew-tag what )],
            qr/\QYou must provide a valid --berrybrew-tag when the OS is set to Windows./,
            '--os Windows requires a --berrybreq-tag flag that is a version',
        ],
        [
            [qw( --os Windows --berrybrew-tag v1.0 --include-threads )],
            qr/\QYou cannot pass --include-threads when generating a matrix for Windows./,
            '--os Windows does not allow passing --include-threads',
        ],
        [
            [ qw( --os Linux --perls ), '5.8,5.10', qw( --from-perl 5.8 ) ],
            qr/\QYou cannot pass both `perls` and `from_perl` parameters to the Linux stage./,
            'cannot pass both --perls and --from-perl',
        ],
        [
            [ qw( --os Linux --perls ), '5.8,5.10', qw( --to-perl 5.8 ) ],
            qr/\QYou cannot pass both `perls` and `to_perl` parameters to the Linux stage./,
            'cannot pass both --perls and --to-perl',
        ],
        [
            [qw( --os Linux )],
            qr/\QTried to generate the Linux matrix but none of `perls`, `from_perl`, or `to_perl` were set./,
            'must pass --perls, --from-perl, or --to-perl',
        ],
    );

    for my $t (@constructor_tests) {
        local @ARGV = $t->[0]->@*;
        like(
            dies { M::TestMatrixPrinter->new },
            $t->[1],
            $t->[2],
        );
    }
};

subtest '_build_perl_data from MetaCPAN - errors' => sub {
    my %response;

    no warnings 'redefine';
    local *M::Curl::post = sub {
        return \%response;
    };

    my $self = bless { os => 'Linux' }, 'M::TestMatrixPrinter';
    %response = (
        success => 0,
        status  => 400,
    );

    my $expect_uri = 'https://fastapi.metacpan.org/v1/release/_search';
    like(
        dies { $self->_build_perl_data },
        qr{\QError POSTing to $expect_uri with body: \E.+\n\Qstatus = 400},
        'call to MetaCPAN is checked for success',
    );

    %response = (
        success => 1,
        status  => 200,
        content => q{},
    );
    like(
        dies { $self->_build_perl_data },
        qr{\QPOST to $expect_uri did not return any content},
        'call to MetaCPAN is expected to return content',
    );

    %response = (
        success => 1,
        status  => 200,
        content => q{[this is not JSON]},
    );
    like(
        dies { $self->_build_perl_data },
        qr{\QCould not parse body of $expect_uri response as JSON: 'true' expected},
        'call to MetaCPAN is expected to return valid JSON',
    );

    for my $content ( '[]', '{}', '{ "hits": [] }', '{ "hits": 42 }' ) {
        %response = (
            success => 1,
            status  => 200,
            content => $content,
        );
        like(
            dies { $self->_build_perl_data },
            qr{\QPOST to $expect_uri did not return content with the expected data structure - got `$content`},
            qq[call to MetaCPAN is expected to return JSON object like `{ "hits": { ... } }`, not `$content`],
        );
    }

    %response = (
        success => 1,
        status  => 200,
        content => '{ "hits": { "total": 0 } }',
    );
    like(
        dies { $self->_build_perl_data },
        qr{\QPOST to $expect_uri did not return any hits for perl releases},
        'call to MetaCPAN is expected to find perl releases',
    );
};

subtest '_build_perl_data from MetaCPAN - success' => sub {
    my %response;

    no warnings 'redefine';
    local *M::Curl::post = sub {
        return \%response;
    };

    my $self = bless { os => 'Linux' }, 'M::TestMatrixPrinter';

    my %hits = (
        map { $_->{name} => $_ } {
            name             => 'perl-5.6.1.tar.gz',
            version_numified => 5.006001,
            maturity         => 'released',
            date             => '2012-01-01T01:02:03',
        },
        {
            name             => 'perl-5.8.8.tar.gz',
            version_numified => 5.008008,
            maturity         => 'released',
            date             => '2013-01-01T01:02:03',
        },
        {
            name             => 'perl-5.8.9.tar.gz',
            version_numified => 5.008009,
            maturity         => 'released',
            date             => '2013-02-01T01:02:03',
        },
        {
            name             => 'perl-5.10.0.tar.gz',
            version_numified => 5.010000,
            maturity         => 'released',
            date             => '2014-01-01T01:02:03',
        },
        {
            name             => 'perl-5.10.1.tar.gz',
            version_numified => 5.010001,
            maturity         => 'released',
            date             => '2014-02-01T01:02:03',
        },
        {
            name             => 'perl-5.24.0.tar.gz',
            version_numified => 5.024000,
            maturity         => 'released',
            date             => '2015-01-01T01:02:03',
        },
        {
            name             => 'perl-5.24.1.tar.gz',
            version_numified => 5.024001,
            maturity         => 'released',
            date             => '2015-02-01T01:02:03',
        },
        {
            name             => 'perl-5.24.2-RC1.tar.gz',
            version_numified => 5.024002,
            maturity         => 'developer',
            date             => '2015-02-01T01:02:03',
        },
        {
            name             => 'perl-5.30.1.tar.gz',
            version_numified => 5.030001,
            maturity         => 'developer',
            date             => '2030-02-01T01:02:03',
        },
    );
    %response = (
        success => 1,
        status  => 200,
        content => _metacpan_json( values %hits ),
    );

    ## no critic (Variables::ProtectPrivateVars)
    local *T::TestMatrixPrinter::_repo_date = sub {
        return Time::Piece->strptime(
            '2020-01-01T00:00:00',
            '%Y-%m-%dT%H:%M:%S',
        );
    };
    ## use critic

    is(
        $self->_build_perl_data,
        hash {
            field identifiers => hash {

                # We don't include anything before 5.8.9.
                field '5.6'   => DNE();
                field '5.6.1' => DNE();

                # For 5.8.x and 5.10.x we only include the final minor release
                # in the series.
                field '5.8.8'  => DNE();
                field '5.8'    => T();
                field '5.8.9'  => T();
                field '5.10.0' => DNE();
                field '5.10'   => T();
                field '5.10.1' => T();

                # For other stable release series we include all versions.
                field '5.24'   => T();
                field '5.24.0' => T();
                field '5.24.1' => T();
                field '5.24.2' => DNE();

                # We skip any Perl released after the latest commit in the
                # repo.
                field '5.30.1' => DNE();
                field dev      => T();
                field blead    => T();
                end();
            };
            field perls => hash {
                field '5.6'   => DNE();
                field '5.6.1' => DNE();
                field '5.8.8' => DNE();
                field '5.8.9' => {
                    $hits{'perl-5.8.9.tar.gz'}->%*,
                    minor              => 8,
                    version            => '5.8.9',
                    is_latest_in_minor => T(),
                };
                field '5.10.0' => DNE();
                field '5.10.1' => {
                    $hits{'perl-5.10.1.tar.gz'}->%*,
                    minor              => 10,
                    version            => '5.10.1',
                    is_latest_in_minor => T(),
                };
                field '5.24.0' => {
                    $hits{'perl-5.24.0.tar.gz'}->%*,
                    minor              => 24,
                    version            => '5.24.0',
                    is_latest_in_minor => DNE(),
                };
                field '5.24.1' => {
                    $hits{'perl-5.24.1.tar.gz'}->%*,
                    minor              => 24,
                    version            => '5.24.1',
                    is_latest_in_minor => T(),
                };
                field '5.24.2' => DNE();
                end();
            };
            field latest_stable_version => {
                $hits{'perl-5.24.1.tar.gz'}->%*,
                minor              => 24,
                version            => '5.24.1',
                is_latest_in_minor => T(),
            };
            end();
        },
        'got expected perl data from MetaCPAN response',
    );
};

subtest '_build_perl_data from berrybrew perls.json file - errors' => sub {
    my %response;

    no warnings 'redefine';
    local *M::Curl::get = sub {
        return \%response;
    };

    my $self = bless {
        os            => 'Windows',
        berrybrew_tag => 'v1.29',
        },
        'M::TestMatrixPrinter';

    %response = (
        success => 0,
        status  => 400,
    );

    my $expect_uri
        = 'https://raw.githubusercontent.com/stevieb9/berrybrew/v1.29/data/perls.json';
    like(
        dies { $self->_build_perl_data },
        qr{\QError GETting $expect_uri\E\n\Qstatus = 400},
        'call to github berrybrew repo is checked for success',
    );

    %response = (
        success => 1,
        status  => 200,
        content => q{},
    );
    like(
        dies { $self->_build_perl_data },
        qr{\QGET $expect_uri did not return any content},
        'call to berrybrew is expected to return content',
    );

    %response = (
        success => 1,
        status  => 200,
        content => q{[this is not JSON]},
    );
    like(
        dies { $self->_build_perl_data },
        qr{\QCould not parse body of $expect_uri response as JSON: 'true' expected},
        'call to berrybrew is expected to return valid JSON',
    );

    for my $content ( '[]', '{}', '[42]', '[ { "foo": 42 } ]' ) {
        %response = (
            success => 1,
            status  => 200,
            content => $content,
        );
        like(
            dies { $self->_build_perl_data },
            qr{\QGET $expect_uri did not return content with the expected data structure - got `$content`},
            qq[call to berrybrew is expected to return JSON object like `[ { ver => ... } ]`, not `$content`],
        );
    }
};

subtest '_build_perl_data from berrybrew perls.json file - success' => sub {
    my %response;

    no warnings 'redefine';
    local *M::Curl::get = sub {
        return \%response;
    };

    my $self = bless {
        os            => 'Windows',
        berrybrew_tag => 'v1.29',
        },
        'M::TestMatrixPrinter';

    my $content = <<'EOF';
[
  {
    "name": "5.30.1_64",
    "url": "http://strawberryperl.com/download/5.30.1.1/strawberry-perl-5.30.1.1-64bit-portable.zip",
    "file": "strawberry-perl-5.30.1.1-64bit-portable.zip",
    "csum": "906bd55f35b4b51c60496479bd45212a91666a7b",
    "ver": "5.30.1"
  },
  {
    "name": "5.30.1_64_PDL",
    "url": "http://strawberryperl.com/download/5.30.1.1/strawberry-perl-5.30.1.1-64bit-PDL.zip",
    "file": "strawberry-perl-5.30.1.1-64bit-PDL.zip",
    "csum": "7fa0fa9f7171fbc2001ba2971db8f20a39021f4b",
    "ver": "5.30.1"
  },
  {
    "name": "5.24.4_64",
    "url": "http://strawberryperl.com/download/5.24.4.1/strawberry-perl-5.24.4.1-64bit-portable.zip",
    "file": "strawberry-perl-5.24.4.1-64bit-portable.zip",
    "csum": "9425fb48c1cac51e24d799261ff9c9bdecaadf58",
    "ver": "5.24.4"
  },
  {
    "name": "5.24.4_64_PDL",
    "url": "http://strawberryperl.com/download/5.24.4.1/strawberry-perl-5.24.4.1-64bit-PDL.zip",
    "file": "strawberry-perl-5.24.4.1-64bit-PDL.zip",
    "csum": "b4f4a56500a58492c060917183d3d0e6aeb2b680",
    "ver": "5.24.4"
  },
  {
    "name": "5.24.4_32",
    "url": "http://strawberryperl.com/download/5.24.4.1/strawberry-perl-no64-5.24.4.1-32bit-portable.zip",
    "file": "strawberry-perl-no64-5.24.4.1-32bit-portable.zip",
    "csum": "e593a1833ec67bca0d61d708e9ca5b92b2ced189",
    "ver": "5.24.4"
  },
  {
    "name": "5.10.1_32",
    "url": "http://strawberryperl.com/download/5.10.1.5/strawberry-perl-5.10.1.5.zip",
    "file": "strawberry-perl-5.10.1.5.zip",
    "csum": "6bcc8fd448a0f6f5e57b241697bcd6e71602186f",
    "ver": "5.10.1"
  },
  {
    "name": "5.8.9_32",
    "url": "http://strawberryperl.com/download/5.8.9/strawberry-perl-5.8.9.5.zip",
    "file": "strawberry-perl-5.8.9.5.zip",
    "csum": "daeaaa54052c749b1588ccd0a73c37ec349aedaa",
    "ver": "5.8.9"
  }
]
EOF

    %response = (
        success => 1,
        status  => 200,
        content => $content,
    );
    is(
        $self->_build_perl_data,
        hash {
            field identifiers => hash {
                field '5.8'    => T();
                field '5.8.9'  => T();
                field '5.10'   => T();
                field '5.10.1' => T();

                # For other stable release series we include all versions.
                field '5.24'   => T();
                field '5.24.4' => T();

                field '5.30'   => T();
                field '5.30.1' => T();

                field dev   => DNE();
                field blead => DNE();
                end();
            };
            field perls => hash {
                field '5.8.9' => {
                    date               => '1970-01-01T00:00:00',
                    version            => '5.8.9',
                    name               => '-5.8.9',
                    version_numified   => 5.008009,
                    maturity           => 'released',
                    berrybrew_version  => '5.8.9_32',
                    minor              => 8,
                    is_latest_in_minor => T(),
                };
                field '5.10.1' => {
                    date               => '1970-01-01T00:00:00',
                    name               => '-5.10.1',
                    version_numified   => 5.010001,
                    maturity           => 'released',
                    berrybrew_version  => '5.10.1_32',
                    minor              => 10,
                    version            => '5.10.1',
                    is_latest_in_minor => T(),
                };
                field '5.24.4' => {
                    date               => '1970-01-01T00:00:00',
                    name               => '-5.24.4',
                    version_numified   => 5.024004,
                    maturity           => 'released',
                    berrybrew_version  => '5.24.4_64',
                    minor              => 24,
                    version            => '5.24.4',
                    is_latest_in_minor => T(),
                };
                field '5.30.1' => {
                    date               => '1970-01-01T00:00:00',
                    name               => '-5.30.1',
                    version_numified   => 5.030001,
                    maturity           => 'released',
                    berrybrew_version  => '5.30.1_64',
                    minor              => 30,
                    version            => '5.30.1',
                    is_latest_in_minor => T(),
                };
                end();
            };
            field latest_stable_version => {
                date               => '1970-01-01T00:00:00',
                name               => '-5.30.1',
                version_numified   => 5.030001,
                maturity           => 'released',
                berrybrew_version  => '5.30.1_64',
                minor              => 30,
                version            => '5.30.1',
                is_latest_in_minor => T(),
            };
            end();
        },
        'got expected perl data from berrybrew perls.json file',
    );
};

sub _metacpan_json {
    my @perls   = @_;
    my %content = (
        hits => {
            total => scalar @perls,
            hits  => [ map { { fields => $_ } } @perls ],
        },
    );
    return encode_json( \%content );
}

done_testing();
