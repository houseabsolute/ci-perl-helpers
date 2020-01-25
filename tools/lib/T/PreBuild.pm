package T::PreBuild;

use strict;
use warnings FATAL => 'all';
use autodie qw( :all );

use Data::Dumper::Concise qw( Dumper );
use Module::CPANfile;

use Moo;
use MooX::StrictConstructor;

with 'R::HelperScript';

sub run {
    my $self = shift;

    $self->_debug_step;

    $self->_perl_v_to(
        $self->tools_perl,
        $self->cache_dir->child('tools-perl-version'),
    );

    # This should be everything needed to go from the checkout to having a
    # final dist dir where we can run tests.
    #
    # If the thing being tested does not use dzil, minilla, or
    # Module::Install, _and_ it doesn't declare its configure-time prereqs in
    # a cpanfile or META.{json,yml} that's checked into the repo, then we
    # won't be able to build it.
    my %authordeps = $self->_authordeps;
    $self->_debug( 'authordeps = ' . Dumper( \%authordeps ) );

    my %configure_requires = $self->_configure_requires;
    $self->_debug( 'configure requires = ' . Dumper( \%configure_requires ) );

    my $cpanfile = $self->cache_dir->child('build-deps-cpanfile');
    $self->_debug("Writing all author deps to $cpanfile");
    $cpanfile->spew( $self->_cpanfile( %authordeps, %configure_requires ) );

    return 0;
}

# This list comes from the travis-perl repo.
my %ModuleInstallCommands = (
    write_credits_file   => 'Module::Install::Credits',
    write_copyright_file => 'Module::Install::Copyright',
    cc_warnings          => 'Module::Install::XSUtil',
    use_ppport           => 'Module::Install::XSUtil',
    cc_define            => 'Module::Install::XSUtil',
    cc_include_paths     => 'Module::Install::XSUtil',
    cc_src_paths         => 'Module::Install::XSUtil',
    install_headers      => 'Module::Install::XSUtil',
    prepan               => 'Module::Install::PrePAN',
    use_testml_tap       => 'Module::Install::TestML',
    install_sharefile    => 'Module::Install::ShareFile',
    auto_set_repository  => 'Module::Install::Repository',
    auto_set_homepage    => 'Module::Install::Homepage',
    checklibs            => 'Module::Install::CheckLib',
    catalyst             => 'Module::Install::Catalyst',
    extra_tests          => 'Module::Install::ExtraTests',
    auto_set_bugtracker  => 'Module::Install::Bugtracker',
    githubmeta           => 'Module::Install::GithubMeta',
    standard_test        => 'Module::Install::StandardTests',
    use_test_base        => 'Module::Install::TestBase',
    cpanfile             => 'Module::Install::CPANfile',
    check_conflicts      => 'Module::Install::CheckConflicts',
    manifest_skip        => 'Module::Install::ManifestSkip',
    auto_tester          => 'Module::Install::AutomatedTester',
    readme_from          => 'Module::Install::ReadmeFromPod',
    authority            => 'Module::Install::Authority',
    auto_license         => 'Module::Install::AutoLicense',
    author_requires      => 'Module::Install::AuthorRequires',
    author_tests         => 'Module::Install::AuthorTests',
    contributors         => 'Module::Install::Contributors',
    installdirs          => 'Module::Install::InstallDirs',
);

sub _authordeps {
    my $self = shift;

    # We reinstall the various tools in case new releases have been made since
    # our base image was built (at least for Docker builds).
    if ( $self->is_dzil ) {
        my @raw_deps;
        $self->_with_brewed_perl_perl5lib(
            $self->tools_perl,
            sub {
                @raw_deps = $self->_run3(
                    [
                        $self->_perl_local_script(
                            $self->tools_perl, 'dzil'
                        ),
                        'authordeps',
                        '--versions'
                    ],
                );
            },
        );

        my %authordeps;
        for my $raw (@raw_deps) {
            next if $raw =~ /^inc::/;

            chomp $raw;
            my ( $module, $version ) = split /\s*[=~]\s*/, $raw;
            $authordeps{$module} = $version || '0';
        }

        return (
            'Dist::Zilla' => '0',
            %authordeps,
        );
    }
    elsif ( $self->is_minilla ) {
        return ( 'Minilla' => '0' );
    }
    elsif ( $self->is_module_install ) {
        return (
            map { $_ => '0' } $self->_module_install_authordeps,
            'Module::Install'
        );
    }

    return ();
}

sub _module_install_authordeps {
    my $self = shift;

    my $content = $self->checkout_dir->child('Makefile.PL')->slurp_utf8;
    return map { $ModuleInstallCommands{$_} }
        grep { $content =~ /\Q$_/ } keys %ModuleInstallCommands;
}

sub _configure_requires {
    my $self = shift;

    if ( my $meta = $self->_load_cpan_meta_in( $self->checkout_dir ) ) {
        return $self->_configure_prereqs_from( $meta->effective_prereqs );
    }

    my $cpanfile = $self->checkout_dir->child('cpanfile');

    # See https://github.com/tokuhirom/Minilla/issues/275 for why we need to
    # ignore cpanfiles from Minilla-built distros.
    if ( $cpanfile->is_file && !$self->is_minilla ) {
        my $prereqs = Module::CPANfile->load($cpanfile)->prereqs;

        return $self->_configure_prereqs_from($prereqs);
    }

    return ();
}

sub _configure_prereqs_from {
    my $self    = shift;
    my $prereqs = shift;

    my %requires;
    for my $type (qw( recommends requires suggests )) {
        my $reqs = $prereqs->requirements_for( 'configure', $type );
        %requires = ( %requires, %{ $reqs->as_string_hash } );
    }

    return %requires;
}

sub _cpanfile {
    my $self     = shift;
    my %requires = @_;

    my $cpanfile = q{};
    for my $m ( sort keys %requires ) {
        my $dep
            = $requires{$m} =~ /[=<>!]/ ? $requires{$m} : ">= $requires{$m}";
        $cpanfile .= qq[requires '$m', '$dep';\n];
    }

    return $cpanfile;
}

1;
