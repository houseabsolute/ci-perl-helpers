use strict;
use warnings;

use FindBin qw( $Bin );
use lib "$Bin/../lib";

use T::PreBuild;

exit T::PreBuild->new->run;
