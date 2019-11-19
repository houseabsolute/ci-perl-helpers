use strict;
use warnings;

use FindBin qw( $Bin );
use lib "$Bin/../lib";

use T::InstallDynamicPrereqs;

exit T::InstallDynamicPrereqs->new->run;
