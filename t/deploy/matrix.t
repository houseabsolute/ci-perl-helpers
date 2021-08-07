use v5.30.1;
use strict;
use warnings 'FATAL' => 'all';
use feature 'postderef', 'signatures';
use autodie qw( :all );

use FindBin qw( $Bin );
use lib "$Bin/../../deploy/lib", "$Bin/../../shared/lib";

use D::PrintPerlsMatrix;
use Mock::Quick;
use Test2::V0;

## no critic (TestingAndDebugging::ProhibitNoWarnings)
no warnings 'experimental::postderef', 'experimental::signatures';
## use critic

my @releases;
my $release = qstrict(
    total => qmeth { return scalar @releases },
    next  => qmeth { return shift @releases },
);
my $client = qstrict( release => qmeth { return $release } );

{
    @releases = _make_releases(
        qw(
            5.8.8
            5.8.9
            5.10.0
            5.10.1
            5.24.0
            5.24.1
            5.24.2
            5.26.0-RC1
            5.26.0-RC2
            5.29.0
            5.29.1
            5.30.0
            5.30.1
            5.31.1
            5.31.2
        )
    );

    # These are used in R::Tagger.
    my @remote_heads = (
        "ed6ab1c5c282ca4607756e1d35d8da91eb3d77cb\trefs/heads/better-junit\n",
        "f53dbd18aec72c4d5278d5949ac3cd6cdfb948db\trefs/heads/fix-branch-name\n",
        "6f19ea49ea83b3cd30200237d69df3cab3ee29ae\trefs/heads/fix-set-image-version\n",
        "f99d5afca40b4b3f34e49230a5803a09d006b0b0\trefs/heads/install-xt-tools\n",
        "4760b89ce18de3cbf3be5c51f0f0a7cb17d17c18\trefs/heads/master\n",
    );
    my $commit = '4760b89ce18de3cbf3be5c51f0f0a7cb17d17c18';
    my $tag    = 'v1.1.1';

    local *git::ls_remote = sub {@remote_heads};
    local *git::rev_parse = sub {$commit};
    local *git::describe  = sub {$tag};

    my $branch = 'master';

    my $ppm = D::PrintPerlsMatrix->new( _client => $client );

    my $matrix      = $ppm->_create_matrix;
    my @expect_keys = sort map { ( $_, $_ . '_threads' ) }
        map { 'perl_' . $_ }
        qw( 5_8_9 5_10_1 5_24_0 5_24_1 5_24_2 5_30_0 5_30_1 5_31_2 );

    # There is no blead_threads since the blead image does not actually have a
    # Perl pre-installed.
    push @expect_keys, 'perl_blead';
    is(
        $matrix,
        hash {
            # For 5.8.x and 5.10.x we only include the final minor release in
            # the series.
            field perl_5_8_8          => DNE();
            field perl_5_8_8_threads  => DNE();
            field perl_5_8_9          => E();
            field perl_5_8_9_threads  => E();
            field perl_5_10_0         => DNE();
            field perl_5_10_0_threads => DNE();
            field perl_5_10_1         => E();
            field perl_5_10_1_threads => E();

            # For other stable release series we include all versions.
            field perl_5_24_0         => E();
            field perl_5_24_0_threads => E();
            field perl_5_24_1         => E();
            field perl_5_24_1_threads => E();
            field perl_5_24_2         => E();
            field perl_5_24_2_threads => E();
            field perl_5_26_0         => DNE();
            field perl_5_26_0_threads => DNE();

            # For dev releases we only include the very latest one.
            field perl_5_29_0         => DNE();
            field perl_5_29_1         => DNE();
            field perl_5_31_1         => DNE();
            field perl_5_31_1_threads => DNE();

            field perl_5_30_0 => hash {
                field perl => '5.30.0';
                field tags => join q{},
                    map {"$_\n"} ( "5.30.0-${branch}", "5.30.0-${tag}" );
                field threads => F();
                end;
            };
            field perl_5_30_0_threads => hash {
                field perl => '5.30.0';
                field tags => join q{},
                    map {"$_\n"} (
                    "5.30.0-threads-${branch}",
                    "5.30.0-threads-${tag}",
                    );
                field threads => T();
                end;
            };

            # The most recent release in a stable series gets the "5.x" tag as
            # well as the "5.x.y" tag.
            field perl_5_30_1 => hash {
                field perl => '5.30.1';
                field tags => join q{},
                    map {"$_\n"} (
                    "5.30-${branch}",
                    "5.30-${tag}",
                    "5.30.1-${branch}",
                    "5.30.1-${tag}",
                    );
                field threads => F();
                end;
            };
            field perl_5_30_1_threads => hash {
                field perl => '5.30.1';
                field tags => join q{},
                    map {"$_\n"} (
                    "5.30-threads-${branch}",
                    "5.30-threads-${tag}",
                    "5.30.1-threads-${branch}",
                    "5.30.1-threads-${tag}",
                    );
                field threads => T();
                end;
            };

            # The most recent dev release is tagged as "dev".
            field perl_5_31_2 => hash {
                field perl => '5.31.2';
                field tags => join q{}, map {"$_\n"} (
                    "dev-${branch}",
                    "dev-${tag}",
                );
                field threads => F();
                end;
            };
            field perl_5_31_2_threads => hash {
                field perl => '5.31.2';
                field tags => join q{}, map {"$_\n"} (
                    "dev-threads-${branch}",
                    "dev-threads-${tag}",
                );
                field threads => T();
                end;
            };

            # There is only one blead image that has all the tags (with and
            # w/o threads), because that Docker image won't actually contain a
            # Perl. Instead, Perl is built at CI time and the requested perl's
            # name (blead or blead-threads) is used to figure out if it should
            # be compiled with threads enabled.
            field perl_blead => hash {
                field perl => 'blead';
                field tags => join q{}, map {"$_\n"} (
                    "blead-${branch}",
                    "blead-${tag}",
                    "blead-threads-${branch}",
                    "blead-threads-${tag}",
                );
                field threads => F();
                end;
            };
            end;
        },
        'got expected values in matrix',
    );
}

done_testing();

sub _make_releases (@versions) {
    return map {
        qstrict(
            name    => 'perl-' . $_,
            version => $_
                =~ s/5\.(\d+).(\d+)/sprintf('5.%03d%03d', $1, $2)/er,
        );
    } @versions;
}
