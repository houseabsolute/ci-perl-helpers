use v5.26.1;
use strict;
use warnings;

use FindBin qw( $Bin );
use lib "$Bin/../lib";

use M::TestMatrixPrinter;

my $p = M::TestMatrixPrinter->new
    or exit 1;
exit $p->run;
