use strict;
use warnings;

use FindBin qw( $Bin );
use lib "$Bin/../lib";

use T::ShowEnv;

exit T::ShowEnv->new->run;
