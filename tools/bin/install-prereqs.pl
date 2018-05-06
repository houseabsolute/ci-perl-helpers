use strict;
use warnings;

use FindBin qw( $Bin );
use lib "$Bin/../lib";

use T::InstallPrereqs;

exit T::InstallPrereqs->new->run;
