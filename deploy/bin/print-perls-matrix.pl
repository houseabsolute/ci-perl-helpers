use strict;
use warnings;

use FindBin qw( $Bin );
use lib "$Bin/../lib";

use D::PrintPerlsMatrix;

exit D::PrintPerlsMatrix->new_with_options->run;
