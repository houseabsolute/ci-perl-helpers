package T::RunTests;

use strict;
use warnings FATAL => 'all';
use autodie qw( :all );

use Path::Tiny qw( tempdir );
use Path::Tiny::Rule;

use Moo;
use MooX::StrictConstructor;

with 'R::HelperScript';

sub run {
    my $self = shift;

    $self->_debug_step;

    my $dir = $self->_pushd( $self->extracted_dist_dir );

    local $ENV{HARNESS_PERL_SWITCHES} = $ENV{HARNESS_PERL_SWITCHES} || q{};
    if ( $self->coverage ) {
        $ENV{HARNESS_PERL_SWITCHES} .= q{:}
            if $ENV{HARNESS_PERL_SWITCHES};
        $ENV{HARNESS_PERL_SWITCHES}
            .= '-MDevel::Cover=-ignore,^x?t/,-blib,0,-dir,'
            . $self->coverage_dir;
        $self->_debug("HARNESS_PERL_SWITCHES=$ENV{HARNESS_PERL_SWITCHES}");
        $self->coverage_dir->mkpath( 0, 0755 );
    }

    my $tempdir = tempdir();
    my $archive = $tempdir->child('prove.tar.gz');
    my $exit;
    $self->_with_brewed_perl_perl5lib(
        $self->runtime_perl,
        sub {
            $exit = $self->_system_no_die(
                $self->_brewed_perl( $self->runtime_perl ),
                'prove',
                '--archive', $archive,
                '--blib',
                '--jobs', 10,
                '--merge',
                '--recurse',
                '--verbose',
                @{ $self->test_paths },
            );
        },
    );

    if ( $exit == -1 ) {
        die "Could not run prove at all: $!";
    }
    elsif ( $exit > 0 ) {
        my $code   = $? >> 8;
        my $signal = $? & 127;
        my $msg    = "Running tests with prove failed (exit code = $code";
        $msg .= ", signal = $signal" if $signal;
        $msg .= ').';
        if ( $self->allow_test_failures ) {
            print "##vso[task.logissue type=warning]$msg\n"
                or die $!;
        }
        else {
            die $msg;
        }
    }

    $self->_tap2junit($archive);

    return 0;
}

sub _tap2junit {
    my $self    = shift;
    my $archive = shift;

    my $dir = $self->_pushd( $archive->parent );

    $self->_system(
        'tar',
        '--extract',
        '--gzip',
        '--verbose',
        '--file', $self->_posix_path($archive),
    );

    my @t_files = Path::Tiny::Rule->new->file->name(qr/\.t$/)->all('.');

    # Windows max claims to be 32,000 (per running `getconf ARG_MAX) but
    # experimentation shows that anything close to that doesn't work, but
    # 5,000 does.
    my $command_limit = $^O eq 'MSWin32' ? 5_000 : 100_000;
    while (@t_files) {
        my @command
            = $self->_perl_local_script( $self->tools_perl, 'tap2junit' );
        my $length = length $command[0];

        while ( $length <= $command_limit && @t_files ) {
            push @command, shift @t_files;
            $length += length $command[-1];
        }

        $self->_with_brewed_perl_perl5lib(
            $self->tools_perl,
            sub {
                $self->_system(@command);
            },
        );
    }

    my $j = $self->workspace_root->child('junit');
    $self->_debug("Making $j for junit files");
    $j->mkpath( 0, 0755 );

    for my $xml ( Path::Tiny::Rule->new->file->name(qr/\.xml$/)->all('.') ) {
        my $to = $j->child($xml);
        $to->parent->mkpath( 0, 0755 );
        $self->_debug("Copy $xml to $to");
        $xml->copy($to);
    }

    return undef;
}

1;
