package T::PrintTotalPartitions;

use strict;
use warnings FATAL => 'all';
use autodie qw( :all );

use Getopt::Long   qw( :config pass_through );
use List::AllUtils qw( all );

use Moo;
use MooX::StrictConstructor;

sub run {
    my $self = shift;

    my ( $this_partition, $partitions );
    GetOptions(
        'this-partition:s' => \$this_partition,
        'partitions:s'     => \$partitions,
    );

    my $int_re = qr/\A[1-9][0-9]*\z/;
    unless ( defined $this_partition && $this_partition =~ $int_re ) {
        my $val = length $this_partition ? qq{"$this_partition"} : 'empty';
        _error(
            qq{The "this_partition" parameter must be set to a positive integer but it was $val.}
        );
    }

    my @partitions;
    unless ( defined $partitions && ( @partitions = split /,/, $partitions ) )
    {
        _error(
            q{The 'partitions' parameter must be a non-empty array of integers.}
        );
    }

    for my $i ( 0 .. $#partitions ) {
        unless ( $partitions[$i] =~ /$int_re/ ) {
            my $val
                = length $partitions[$i] ? qq{"$partitions[$i]"} : 'empty';
            _error(
                qq{Element $i of the 'partitions' parameters is $val, which is not an integer value.}
            );
        }

        my $want = $i + 1;
        unless ( $partitions[$i] == $want ) {
            _error(
                qq{The 'partitions' must be a sequential array of integers starting with 1 but element #$i is "$want".}
            );
        }
    }

    print scalar @partitions
        or die $!;

    return 0;
}

sub _error {
    my $msg = shift;
    print qq{##vso[task.logissue type=error;]$msg\n}
        or die $!;
    print "##vso[task.complete result=Failed;]\n"
        or die $!;

    # When running under Azure the vso messages above will trigger the end of
    # the build, but for local testing we need a non-zero exit code.
    exit( $ENV{BUILD_BUILDID} ? 0 : 1 );
}

1;
