package C::NewPerlChecker;

use v5.30.1;
use strict;
use warnings;
use feature 'postderef', 'signatures';
use warnings 'FATAL' => 'all';
use autodie qw( :all );
use namespace::autoclean;

use Data::Dumper::Concise;
use MIME::Base64 qw( encode_base64 );
use HTTP::Tiny;
use JSON::MaybeXS qw( decode_json encode_json );
use Path::Tiny    qw( path );
use Specio::Declare;
use Specio::Library::Builtins;
use Specio::Library::Path::Tiny;

use Moose;
## no critic (TestingAndDebugging::ProhibitNoWarnings)
no warnings 'experimental::postderef', 'experimental::signatures';
## use critic

with 'MooseX::Getopt::Dashes', 'R::PerlReleaseFetcher';

has dry_run => (
    is      => 'ro',
    isa     => t('Bool'),
    default => 0,
);

has quiet => (
    is      => 'ro',
    isa     => t('Bool'),
    default => 0,
);

has _current_perls => (
    is      => 'ro',
    isa     => t( 'ArrayRef', of => object_isa_type('H::PerlRelease') ),
    lazy    => 1,
    builder => '_build_current_perls',
);

has _last_perls => (
    is      => 'ro',
    isa     => t( 'HashRef', of => t('Bool') ),
    lazy    => 1,
    builder => '_build_last_perls',
);

has _last_perls_file => (
    is      => 'ro',
    isa     => t('Path'),
    lazy    => 1,
    default => sub ($self) { $self->_cache_dir->child('last-perls.json') },
);

has _cache_dir => (
    is      => 'ro',
    isa     => t('Path'),
    lazy    => 1,
    builder => '_build_cache_dir',
);

sub run ($self) {
    my @new = grep { !$self->_last_perls->{$_} }
        map { $_->version } $self->_current_perls->@*;

    unless (@new) {
        unless ( $self->quiet ) {
            say 'No new Perl versions since the last check'
                or die $!;
        }
        return 0;
    }

    unless ( $self->quiet ) {
        say "Found new perls: @new"
            or die $!;
    }

    $self->_trigger_build;
    $self->_write_last_perls
        unless $self->dry_run;

    return 0;
}

sub _build_last_perls ($self) {
    return {} unless $self->_last_perls_file->exists;
    my $last_perls = decode_json( $self->_last_perls_file->slurp );
    return { map { $_ => 1 } $last_perls->@* };
}

sub _build_cache_dir {
    my @c
        = $ENV{XDG_CACHE_HOME}
        ? $ENV{XDG_CACHE_HOME}
        : ( $ENV{HOME}, '.cache' );
    push @c, 'ci-perl-helpers';
    return path(@c);
}

sub _build_current_perls ($self) {
    my $dev;
    my @perls;
    for my $r ( $self->_perl_releases->@* ) {
        if ( $r->numeric_version < 5.012 ) {
            next unless $r->version eq '5.8.9' || $r->version eq '5.10.1';
        }

        if ( $r->is_stable ) {
            push @perls, $r;
            next;
        }

        if ($dev) {
            $dev = $r
                if $r->numeric_version > $dev->numeric_version;
        }
        else {
            $dev = $r;
        }
    }
    push @perls, $dev;

    return \@perls;
}

sub _trigger_build ($self) {
    my $tag = $self->_most_recent_tag;

    unless ( $self->quiet ) {
        say "Triggering build for tag $tag"
            or die $!;
    }

    my $auth = $self->_get_auth_header;

    my $resp = $self->_request(
        'POST',
        'https://dev.azure.com/houseabsolute/houseabsolute/_apis/build/builds?api-version=5.1',
        {
            Accept         => 'application/json',
            'Content-Type' => 'application/json',
            $self->_get_auth_header,
        },
        {
            # Definition comes from
            # https://dev.azure.com/houseabsolute/houseabsolute/_apis/build/definitions?api-version=5.1
            definition   => { id => 7 },
            sourceBranch => "refs/tags/$tag",
        },
    );
}

sub _get_auth_header {
    my $token = $ENV{CI_PERL_HELPERS_ACCESS_TOKEN}
        or die "The CI_PERL_HELPERS_ACCESS_TOKEN env var is not set\n";

    return Authorization => 'Basic '
        . encode_base64( 'token:' . $token, q{} );
}

sub _most_recent_tag ($self) {
    my $tags = $self->_request(
        'GET',
        'https://api.github.com/repos/houseabsolute/ci-perl-helpers/tags',
        { Accept => 'application/json' },
    );
    unless ( ref $tags
        && ( ref $tags eq 'ARRAY' )
        && $tags->[0]
        && ref $tags->[0]
        && ( ref $tags->[0] eq 'HASH' )
        && $tags->[0]{name} ) {

        my $msg = "Got unexpected response from GitHub repo tags API:\n";
        $msg .= Dumper($tags);
        die $msg;
    }
    return $tags->[0]{name};
}

sub _request ( $self, $method, $uri, $headers, $content = undef ) {
    my $http = HTTP::Tiny->new;
    my %opts;
    $opts{headers} = $headers
        if $headers;
    $opts{content} = encode_json($content)
        if $content;

    if ( $self->dry_run && $method eq 'POST' ) {
        say "$method $uri"
            or die $!;
        say Dumper( \%opts )
            or die $!;
        return;
    }

    my $resp = $http->request( $method, $uri, \%opts );

    unless ( $resp->{success} ) {
        my $msg
            = "Error making $method request to $uri: status = $resp->{status}\n";
        $msg .= "$resp->{content}\n" if $resp->{content};
        die $msg;
    }

    my $decoded = decode_json( $resp->{content} );
    unless ($decoded) {
        die "$method request to $uri did not return any content";
    }

    return $decoded;
}

sub _write_last_perls ($self) {
    my @content = map { $_->version }
        sort { $a->numeric_version <=> $b->numeric_version }
        $self->_current_perls->@*;

    $self->_last_perls_file->parent->mkpath( 0, 0755 );
    $self->_last_perls_file->spew( encode_json( \@content ) );

    return undef;
}

__PACKAGE__->meta->make_immutable;

1;
