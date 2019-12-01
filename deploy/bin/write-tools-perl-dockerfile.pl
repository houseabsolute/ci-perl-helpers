use strict;
use warnings;

use FindBin qw( $Bin );
use lib "$Bin/../lib";

use D::WriteToolsPerlDockerfile;

exit D::WriteToolsPerlDockerfile->new_with_options->run;
