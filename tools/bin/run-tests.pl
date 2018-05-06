use strict;
use warnings;

use FindBin qw( $Bin );
use lib "$Bin/../lib";

use T::RunTests;

exit T::RunTests->new->run;
