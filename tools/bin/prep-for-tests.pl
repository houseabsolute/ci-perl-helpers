use strict;
use warnings;

use FindBin qw( $Bin );
use lib "$Bin/../lib";

use T::PrepForTests;

exit T::PrepForTests->new->run;
