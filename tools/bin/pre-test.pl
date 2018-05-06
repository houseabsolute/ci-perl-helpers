use strict;
use warnings;

use FindBin qw( $Bin );
use lib "$Bin/../lib";

use T::PreTest;

exit T::PreTest->new->run;
