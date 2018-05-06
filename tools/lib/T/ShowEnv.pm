package T::ShowEnv;

use strict;
use warnings FATAL => 'all';
use autodie qw( :all );

use Moo;
use MooX::StrictConstructor;

with 'R::HelperScript';

sub run {
    my $self = shift;

    $self->_show_env;

    return 0;
}

1;
