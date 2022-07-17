# This code should be runnable with the system perl installed on the latest
# Ubuntu VM on Azure. We want to run this without installing a new Perl or any
# modules, for maximum speed, since this script blocks kicking off parallel
# testing.
package M::Curl;

use v5.26.1;
use strict;
use warnings FATAL => 'all';
use autodie;

use IPC::Open2 qw( open2 );
use Symbol qw( gensym );

sub get {
    my $uri     = shift;
    my $headers = shift;
    return _run_curl( 'GET', $uri, $headers );
}

sub post {
    my $uri     = shift;
    my $headers = shift;
    my $body    = shift;
    return _run_curl( 'POST', $uri, $headers, $body );
}

sub _run_curl {
    my $method  = shift;
    my $uri     = shift;
    my $headers = shift;
    my $body    = shift;

    my @cmd = ( 'curl',
                '--silent',
                '--write-out', "\\n\%{http_code}\\n",
                '-X', $method );
    for my $name ( sort keys %{$headers} ) {
        push @cmd, '-H', "$name: $headers->{$name}";
    }

    if ($body) {
        push @cmd, '-d', $body;
    }

    push @cmd, $uri;

    my $stdout = gensym();
    my $pid    = open2(  $stdout, undef, @cmd );
    my $output;
    while (<$stdout>) {
        $output .= $_;
    }
    waitpid $pid, 0;

    if ($?) {
        my $status = $? >> 8;
        die "Ran [@cmd] and status was $status\n";
    }

    my ($status) = $output =~ s/\n(\d+)\s+\z//ms
        or die "Could not get status from output";

    return {
        success => 1,
        status  => $status,
        content => $output,
    };
}

1;
