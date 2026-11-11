use strict;
use warnings;

use FindBin;
use lib $FindBin::Bin;
use CastClient;

my ($host, $videoId, $workerLog) = @ARGV;

# Redirect inside the child process. LMS wraps its own STDERR in Log::Trapper,
# so this must happen after Proc::Background has successfully spawned us.
if (defined $workerLog && length $workerLog) {
    open STDERR, '>>', $workerLog
        or die "Cannot open worker log '$workerLog': $!";
    select STDERR;
    $| = 1;
    select STDOUT;
}

eval { CastClient->cast_youtube($host, $videoId); 1 }
    or die "YouTube Cast failed: " . ($@ || 'unknown error');

exit 0;
