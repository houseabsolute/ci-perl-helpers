package R::DockerfileWriter;

use v5.30.1;
use strict;
use warnings;
use feature 'postderef', 'signatures';
use warnings 'FATAL' => 'all';
use autodie qw( :all );
use namespace::autoclean;

use Path::Tiny qw( path );
use Specio::Declare;
use Specio::Library::Builtins;

use Moose::Role;
## no critic (TestingAndDebugging::ProhibitNoWarnings)
no warnings 'experimental::postderef', 'experimental::signatures';
## use critic

with 'MooseX::Getopt::Dashes';

has perl => (
    is            => 'ro',
    isa           => t('Str'),
    required      => 1,
    documentation => 'The version of Perl to build the Dockerfile for.',
);

has filename => (
    is            => 'ro',
    isa           => t('Str'),
    default       => 'Dockerfile',
    documentation =>
        'The path to which the Dockerfile content should be written.',
);

requires '_content';

## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
sub _write_dockerfile ($self) {
    my $df = path( $self->filename );

    my $content = $self->_content;
    print "\n$content" or die $!;
    $df->spew($content);

    return undef;
}
## use critic

1;
