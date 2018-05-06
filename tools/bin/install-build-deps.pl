use strict;
use warnings;

use FindBin qw( $Bin );
use lib "$Bin/../lib";

use T::InstallBuildDeps;

exit T::InstallBuildDeps->new->run;
