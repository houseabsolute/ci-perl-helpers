use strict;
use warnings;

use FindBin qw( $Bin );
use lib "$Bin/../lib";

use T::BuildCpanfile;

exit T::BuildCpanfile->new->run;
