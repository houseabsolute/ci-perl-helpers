use strict;
use warnings;

use FindBin qw( $Bin );
use lib "$Bin/../lib";

use D::WriteRuntimePerlDockerfile;

exit D::WriteRuntimePerlDockerfile->new_with_options->run;
