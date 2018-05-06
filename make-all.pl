#!/usr/bin/env perl

use v5.26;

use strict;
use warnings;

use FindBin qw( $Bin );
use lib "$Bin/lib";

use Maker;

exit Maker->new_with_options->run;
