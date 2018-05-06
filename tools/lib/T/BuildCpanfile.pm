package T::BuildCpanfile;

use strict;
use warnings FATAL => 'all';
use autodie qw( :all );

use Module::CPANfile;
use Specio::Library::Path::Tiny;

use Moo;
use MooX::StrictConstructor;

with 'R::HelperScript';

has prereqs_cpanfile => (
    is      => 'ro',
    isa     => t('Path'),
    default => sub { $_[0]->cache_dir->child('prereqs-cpanfile') },
);

sub run {
    my $self = shift;

    $self->_debug_step;

    my $dir = $self->_pushd( $self->extracted_dist_dir );

    $self->_write_cpanfile;
    if ( my @c = $self->_coverage_prereqs ) {
        $self->prereqs_cpanfile->append( map {qq[requires '$_';\n]} @c );
    }

    return 0;
}

sub _write_cpanfile {
    my $self = shift;

    return undef if $self->_write_cpanfile_from_meta;

    # This will be installed already in Docker but not in macOS or Windows.
    $self->cpan_install( $self->tools_perl, 'App::scan_prereqs_cpanfile' );

    my @output;
    $self->_with_brewed_perl_perl5lib(
        $self->tools_perl,
        sub {
            @output = $self->_run3(
                [
                    $self->_perl_local_script(
                        $self->tools_perl, 'scan-prereqs-cpanfile'
                    ),
                ],
            );
        },
    );

    $self->prereqs_cpanfile->spew(@output);

    return undef;
}

sub _write_cpanfile_from_meta {
    my $self = shift;

    my $meta = $self->_load_cpan_meta_in( $self->extracted_dist_dir )
        or return 0;

    $self->prereqs_cpanfile->spew(
        Module::CPANfile->from_prereqs( $meta->prereqs )->to_string );

    return 1;
}

sub _coverage_prereqs {
    my $self = shift;

    my %options = map { lc $_ => $_ } qw(
        Codecov
        Clover
        Coveralls
        Kritika
        SonarGeneric
    );

    my $c = $self->coverage
        or return ();

    my @prereqs = 'Devel::Cover';
    push @prereqs, 'Devel::Cover::Report::' . $options{$c}
        if $options{$c};

    return @prereqs;
}

1;
