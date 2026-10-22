package Plugins::YouTubeCast::Settings;

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.youtubecast');

sub name {
    return 'PLUGIN_YOUTUBECAST';
}

sub page {
    return 'plugins/YouTubeCast/settings/basic.html';
}

sub prefs {
    return ($prefs, qw(enabled target_host));
}

1;
