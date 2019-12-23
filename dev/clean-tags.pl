use v5.30.1;
use strict;
use warnings;

use warnings 'FATAL' => 'all';
use feature 'postderef', 'signatures';
use autodie qw( :all );

use FindBin qw( $Bin );
use lib "$Bin/../deploy/lib";

{
    package C;

    use namespace::autoclean;

    use HTTP::Request;
    use JSON::MaybeXS qw( decode_json encode_json );
    use List::AllUtils qw( max uniq );
    use LWP::UserAgent;

    use Moose;
    ## no critic (TestingAndDebugging::ProhibitNoWarnings)
    no warnings 'experimental::postderef', 'experimental::signatures';
    ## use critic

    with 'MooseX::Getopt', 'R::PerlReleaseFetcher';

    has suffixes => (
        is       => 'ro',
        isa      => 'ArrayRef[Str]',
        required => 1,
    );

    has password => (
        is       => 'ro',
        isa      => 'Str',
        required => 1,
    );

    has _jwt => (
        is      => 'ro',
        isa     => 'Str',
        lazy    => 1,
        builder => '_build_jwt',
    );

    has _ua => (
        is      => 'ro',
        isa     => 'LWP::UserAgent',
        lazy    => 1,
        default => sub { LWP::UserAgent->new },
    );

    sub run ($self) {
        my %perls;
        for my $r ( $self->_perl_releases->@* ) {
            push $perls{ $r->minor }->@*, $r;
        }

        my @minors   = sort     { $a <=> $b } keys %perls;
        my $last_dev = max grep { $_ % 2 } @minors;

        my @tags;
        for my $s ( $self->suffixes->@* ) {
            for my $minor ( sort { $a <=> $b } @minors ) {
                next if $minor % 2 && $minor != $last_dev;
                for my $r ( $perls{$minor}->@* ) {
                    push @tags, $r->version . '-' . $s,
                        $r->version . '-threads-' . $s;
                    push @tags, $r->maj_min . '-' . $s,
                        $r->maj_min . '-threads-' . $s;
                }
            }
            push @tags, 'tools-perl-' . $s;
        }

        for my $t ( sort ( uniq(@tags) ) ) {
            my $uri
                = "https://hub.docker.com/v2/repositories/houseabsolute/ci-perl-helpers-ubuntu/tags/$t/";
            $self->_request(
                'DELETE',
                $uri,
                [ 'Authorization', 'JWT ' . $self->_jwt ],
            );
        }

        return 0;
    }

    sub _build_jwt ($self) {
        my $data = { username => 'autarch', password => $self->password };
        my $body = $self->_request(
            'POST',
            'https://hub.docker.com/v2/users/login/',
            [ 'Content-Type', 'application/json' ],
            encode_json($data),
        );
        return $body->{token};
    }

    sub _request ( $self, @req ) {
        my $req = HTTP::Request->new(@req);
        say "$req[0] $req[1]";
        my $resp = $self->_ua->request($req);
        if ( $resp->is_success ) {
            my $content = $resp->decoded_content;
            return unless length $content;
            return decode_json($content);
        }
        if ( $resp->code == 404 ) {
            say 'Not found';
            return;
        }

        die $resp->as_string;
    }
}

exit C->new_with_options->run;
