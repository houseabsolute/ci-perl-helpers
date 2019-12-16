use strict;
use warnings;

use FindBin qw( $Bin );
use lib "$Bin/../lib";

use T::RunCoverageReport;

exit T::RunCoverageReport->new->run;
