use strict;
use warnings;

use FindBin qw( $Bin );
use lib "$Bin/../lib", "$Bin/../../shared/lib";

use C::NewPerlChecker;

exit C::NewPerlChecker->new_with_options->run;
