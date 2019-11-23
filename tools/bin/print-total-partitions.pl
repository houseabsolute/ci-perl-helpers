use strict;
use warnings;

use FindBin qw( $Bin );
use lib "$Bin/../lib";

use T::PrintTotalPartitions;

exit T::PrintTotalPartitions->new->run;
