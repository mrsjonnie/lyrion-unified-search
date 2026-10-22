use strict;
use warnings;

use FindBin;
use lib $FindBin::Bin;
use CastClient;

my ($host, $videoId) = @ARGV;
eval { CastClient->cast_youtube($host, $videoId); 1 }
    or die "YouTube Cast failed: " . ($@ || 'unknown error');

exit 0;
