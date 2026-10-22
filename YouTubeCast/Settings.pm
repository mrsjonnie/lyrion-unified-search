package Plugins::YouTubeCast::Settings;

use strict;
use base qw(Slim::Web::Settings);

use Slim::Player::Client;
use Slim::Utils::Prefs;

my $prefs = preferences('plugin.youtubecast');

sub name {
    return 'PLUGIN_YOUTUBECAST';
}

sub page {
    return 'plugins/YouTubeCast/settings/basic.html';
}

sub prefs {
    return ($prefs, qw(enabled target_host host_mappings));
}

sub beforeRender {
    my ($class, $params) = @_;
    $params->{youtubecastPlayers} = [
        map {
            {
                name => $_->name || $_->id,
                id   => $_->id,
            }
        } Slim::Player::Client::clients()
    ];
}

1;
