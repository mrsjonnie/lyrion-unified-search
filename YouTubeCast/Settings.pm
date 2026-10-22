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

sub handler {
    my ($class, $client, $params, $pageSetup) = @_;

    if ($params->{saveSettings}) {
        my %mappings;
        for my $line (split /[\r\n]+/, $prefs->get('host_mappings') || '') {
            my ($id, $host) = split /\s*=\s*/, $line, 2;
            $mappings{$id} = $host if defined $host;
        }

        for my $player (Slim::Player::Client::clients()) {
            my $host = $params->{'cast_host_' . _playerKey($player->id)};
            my $playerName = $player->name || $player->id;
            unless (defined $host && $host =~ /\S/) {
                delete $mappings{ $player->id };
                delete $mappings{$playerName} if $playerName ne $player->id;
                next;
            }

            $host =~ s/^\s+|\s+$//g;
            delete $mappings{$playerName} if $playerName ne $player->id;
            $mappings{ $player->id } = $host;
        }
        $params->{pref_host_mappings} = join "\n", map { $_ . '=' . $mappings{$_} } sort keys %mappings;
    }

    return $class->SUPER::handler($client, $params, $pageSetup);
}

sub beforeRender {
    my ($class, $params) = @_;
    my %hosts;
    for my $line (split /[\r\n]+/, $prefs->get('host_mappings') || '') {
        my ($id, $host) = split /\s*=\s*/, $line, 2;
        next unless defined $host;
        $hosts{$id} = $host;
    }

    $params->{youtubecastPlayers} = [
        map {
            my $id = $_->id;
            my $name = $_->name || $id;
            {
                name => $name,
                id   => $id,
                key  => _playerKey($id),
                host => $hosts{$id} || $hosts{$name} || '',
            }
        } Slim::Player::Client::clients()
    ];
}

sub _playerKey {
    my ($id) = @_;
    return unpack 'H*', $id;
}

1;
