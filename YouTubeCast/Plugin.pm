package Plugins::YouTubeCast::Plugin;

use strict;
use warnings;
use base qw(Slim::Plugin::Base);

use File::Basename qw(dirname);
use File::Spec::Functions qw(catfile);
use JSON::XS qw(encode_json);
use Slim::Player::Client;
use Slim::Utils::Log;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;

my $prefs = preferences('plugin.youtubecast');
my $log = Slim::Utils::Log->addLogCategory({
    category     => 'plugin.youtubecast',
    defaultLevel => 'WARN',
    description  => 'YouTube Cast for Chromecast',
});
my @workers;
my $warnedMissingHost = 0;
my %lastCast;

sub initPlugin {
    my $class = shift;

    $prefs->init({
        enabled       => 0,
        host_mappings => '',
    });

    $class->SUPER::initPlugin();

    if (main::WEBUI) {
        require Slim::Web::Pages;
        require Plugins::YouTubeCast::Settings;
        Plugins::YouTubeCast::Settings->new;
        Slim::Web::Pages->addPageFunction('plugins/YouTubeCast/cast.json', \&castHandler);
    }
}

sub shutdownPlugin {
    for my $worker (@workers) {
        eval { $worker->die if $worker && $worker->alive };
    }
    @workers = ();
    %lastCast = ();

    # The worker log is plugin-owned; remove it when the plugin is unloaded.
    my $logDir = eval { Slim::Utils::OSDetect::dirsFor('log') };
    if ($logDir) {
        my $workerLog = catfile($logDir, 'youtubecast-worker.log');
        unlink $workerLog if -f $workerLog;
    }
}

sub getDisplayName {
    return 'PLUGIN_YOUTUBECAST';
}

sub castHandler {
    my ($webClient, $params, $callback, $httpClient, $response) = @_;
    $response->content_type('application/json; charset=utf-8');

    my $reply = sub {
        my ($ok, $message) = @_;
        my $json = encode_json({ ok => $ok ? 1 : 0, message => $message });
        $callback->($webClient, $params, \$json, $httpClient, $response);
    };

    unless ($prefs->get('enabled')) {
        return $reply->(0, 'YouTube Cast is disabled in plugin settings');
    }

    my $videoId = $params->{videoId} || '';
    unless ($videoId =~ /\A[A-Za-z0-9_-]{11}\z/) {
        return $reply->(0, 'Invalid YouTube video ID');
    }

    my $playerId = $params->{player} || '';
    my ($player) = grep {
        defined $_->id && $_->id eq $playerId
    } Slim::Player::Client::clients();

    unless ($player) {
        return $reply->(0, 'The selected LMS player is not available');
    }

    my ($ok, $message) = _startCastForVideoId($player, $videoId);
    return $reply->($ok, $message);
}

sub _startCastForVideoId {
    my ($client, $videoId) = @_;
    return (0, 'YouTube Cast is disabled in plugin settings') unless $prefs->get('enabled');
    return (0, 'Invalid YouTube video ID') unless $videoId && $videoId =~ /\A[A-Za-z0-9_-]{11}\z/;

    my $host = _castHostForClient($client);
    $host =~ s/^\s+|\s+$//g;
    unless (length $host) {
        $log->warn('YouTube Cast is enabled, but no Chromecast host is configured for this player');
        return (0, 'No Chromecast host is configured for the selected LMS player');
    }
    unless (_validHost($host)) {
        $log->error('Configured Chromecast host is invalid');
        return (0, 'The configured Chromecast host is invalid');
    }

    my $clientId = $client && $client->id || 'unknown';
    my $now = time;
    if ($lastCast{$clientId}
        && $lastCast{$clientId}{host} eq $host
        && $lastCast{$clientId}{videoId} eq $videoId
        && $now - $lastCast{$clientId}{time} < 5) {
        return (1, 'This video is already being sent to the TV');
    }

    my $pluginDir = dirname(__FILE__);
    my $workerScript = catfile($pluginDir, 'cast_worker.pl');
    my $workerOptions = { autodie => 1, die_upon_destroy => 0 };
    my $logDir = Slim::Utils::OSDetect::dirsFor('log');
    $workerOptions->{stderr} = catfile($logDir, 'youtubecast-worker.log') if $logDir;

    my $worker = eval {
        require Proc::Background;
        Proc::Background->new({
            %$workerOptions,
            command => [$^X, '-I', $pluginDir, $workerScript, $host, $videoId],
        });
    };

    if (!$worker || $@) {
        my $error = $@ || 'process creation failed without an error from Proc::Background';
        $error =~ s/\s+\z//;
        $log->error("Could not start Chromecast worker ($^X, $workerScript): $error");
        return (0, 'Could not start the Chromecast worker; check the LMS log');
    }

    @workers = grep { $_ && $_->alive } @workers;
    push @workers, $worker;
    $lastCast{$clientId} = { host => $host, videoId => $videoId, time => $now };
    my $playerName = $client && ($client->name || $client->id) || 'unknown LMS player';
    $log->info("Explicit YouTube Cast requested for video $videoId on $playerName ($host)");
    return (1, 'Cast request sent to the TV');
}

sub _castHostForClient {
    my ($client) = @_;
    my $clientId = $client && $client->id;
    my $clientName = $client && $client->name;
    my $mappings = $prefs->get('host_mappings') || '';
    my @entries;

    for my $line (split /[\r\n]+/, $mappings) {
        next if $line =~ /^\s*(?:#|$)/;
        my ($key, $host) = split /\s*=\s*/, $line, 2;
        next unless defined $host;
        $key =~ s/^\s+|\s+$//g;
        $host =~ s/^\s+|\s+$//g;
        push @entries, [$key, $host];
    }

    for my $entry (@entries) {
        return $entry->[1] if $clientId && $entry->[0] eq $clientId;
    }

    for my $entry (@entries) {
        return $entry->[1]
            if $clientName && lc($entry->[0]) eq lc($clientName);
    }

    return '';
}

sub _validHost {
    my ($host) = @_;
    return $host =~ /\A[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?\z/;
}

sub _youtubeVideoId {
    my ($url) = @_;

    return $1 if $url =~ m{(?:youtube://(?:https?://)?|https?://)?(?:(?:www|m|music)\.)?youtube\.com/(?:watch\?[^#]*?\bv=|embed/|v/|shorts/|live/)([A-Za-z0-9_-]{11})(?:[?&#]|\z)}i;
    return $1 if $url =~ m{(?:youtube://(?:https?://)?|https?://)?youtu\.be/([A-Za-z0-9_-]{11})(?:[?&#]|\z)}i;
    return $1 if $url =~ m{\Ayoutube://([A-Za-z0-9_-]{11})(?:[?&]|\z)}i;

    return;
}

1;
