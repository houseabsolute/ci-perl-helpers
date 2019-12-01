package R::Tagger;

use v5.30.1;
use strict;
use warnings;
use feature 'postderef', 'signatures';
use warnings 'FATAL' => 'all';
use autodie qw( :all );
use namespace::autoclean;

use Git::Helpers qw( current_branch_name );
use Git::Sub qw( describe );
use Specio::Library::Builtins;

use Moose::Role;
## no critic (TestingAndDebugging::ProhibitNoWarnings)
no warnings 'experimental::postderef', 'experimental::signatures';
## use critic

has image_version => (
    is      => 'ro',
    isa     => t('Str'),
    lazy    => 1,
    builder => '_build_image_version',
    documentation =>
        'A version to append to the image tag. This will default to the name of the current branch.',
);

sub _build_image_version {
    my $tag = git::describe('--tags');
    return $tag
        if $tag =~ /\Av\d+\.\d+\.\d+\z/;

    return $ENV{BUILD_SOURCEBRANCHNAME}
        ? $ENV{BUILD_SOURCEBRANCHNAME}
        : current_branch_name();
}

my $TagRoot = 'houseabsolute/ci-perl-helpers-ubuntu';

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _tag_root {$TagRoot}

sub _base_image ($self) {
    $self->_tag_root . q{:} . $self->_base_image_tag;
}

sub _base_image_tag ($self) {
    return 'tools-perl-' . $self->image_version;
}
## use critic

1;
