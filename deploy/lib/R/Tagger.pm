package R::Tagger;

use v5.30.1;
use strict;
use warnings;
use feature 'postderef', 'signatures';
use warnings 'FATAL' => 'all';
use autodie qw( :all );
use namespace::autoclean;

use Git::Sub qw( describe );
use Specio::Library::Builtins;

use Moose::Role;
## no critic (TestingAndDebugging::ProhibitNoWarnings)
no warnings 'experimental::postderef', 'experimental::signatures';
## use critic

has image_versions => (
    is            => 'ro',
    isa           => t( 'ArrayRef', of => t('Str') ),
    lazy          => 1,
    builder       => '_build_image_versions',
    documentation =>
        'A version to append to the image tag. This will default to the name of the current branch.',
);

sub _build_image_versions {
    die "The BUILD_SOURCEBRANCHNAME env var must be set when building images"
        unless $ENV{BUILD_SOURCEBRANCHNAME};
    my @versions = $ENV{BUILD_SOURCEBRANCHNAME};

    my $tag = git::describe('--tags');
    if ($tag eq $ENV{BUILD_SOURCEBRANCHNAME}) {
        # We should not be tagging any other branches.
        push @versions, 'master';
    } else {
        unshift @versions, $tag
            if $tag =~ /\Av\d+\.\d+\.\d+\z/;
    }

    return [ sort @versions ];
}

my $TagRoot = 'ghcr.io/houseabsolute/ci-perl-helpers-ubuntu';

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _tag_root {$TagRoot}

sub _base_image ($self) {
    $self->_tag_root . q{:} . ( $self->_base_image_tags )[0];
}

sub _base_image_tags ($self) {
    return map { 'tools-perl-' . $_ } $self->image_versions->@*;
}
## use critic

1;
