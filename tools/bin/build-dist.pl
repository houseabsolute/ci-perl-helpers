use strict;
use warnings;

use FindBin qw( $Bin );
use lib "$Bin/../lib";

use T::BuildDist;

exit T::BuildDist->new->run;
