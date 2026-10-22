package Plugins::YouTubeCast::Plugin;

use strict;
use warnings;
use base qw(Slim::Plugin::Base);

use File::Basename qw(dirname);
use File::Spec::Functions qw(catfile);
use Slim::Control::Request;
use Slim::Utils::Log;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;
use Slim::Player::Playlist;
use Slim::Schema;

my $prefs = preferences('plugin.youtubecast');
my $log = Slim::Utils::Log->addLogCategory({
    category     => 'plugin.youtubecast',
    defaultLevel => 'WARN',
    description  => 'YouTube Cast for Chromecast',
});
my @workers;
my $warnedMissingHost = 0;

sub initPlugin {
    my $class = shift;

    $prefs->init({
        enabled     => 0,
        target_host => '',
    });

    $class->SUPER::initPlugin();

    if (main::WEBUI) {
        require Plugins::YouTubeCast::Settings;
        Plugins::YouTubeCast::Settings->new;
    }

    Slim::Control::Request::subscribe(\&_onPlaylistControl, [['playlistcontrol']]);
    Slim::Control::Request::subscribe(\&_onPlaylistPlay, [['playlist'], ['play', 'load']]);
    Slim::Control::Request::subscribe(\&_onPlaylistJump, [['playlist'], ['jump']]);
}

sub shutdownPlugin {
    Slim::Control::Request::unsubscribe(\&_onPlaylistControl);
    Slim::Control::Request::unsubscribe(\&_onPlaylistPlay);
    Slim::Control::Request::unsubscribe(\&_onPlaylistJump);
    for my $worker (@workers) {
        $worker->die if $worker && $worker->alive;
    }
    @workers = ();
}

sub getDisplayName {
    return 'PLUGIN_YOUTUBECAST';
}

sub _onPlaylistControl {
    my ($request) = @_;
    return unless ($request->getParam('cmd') || '') =~ /\A(?:load|play)\z/;

    my $url = _requestTrackUrl($request, 'track_id', 'url');
    _startCastForUrl($url);
}

sub _onPlaylistPlay {
    my ($request) = @_;
    my $url = _requestTrackUrl($request, '_item', 'url');
    _startCastForUrl($url);
}

sub _onPlaylistJump {
    my ($request) = @_;
    my $client = $request->client or return;
    my $index = $request->getParam('_index');
    $index = $request->getParam('index') unless defined $index;
    return unless defined $index && $index =~ /\A\d+\z/;

    my $track = Slim::Player::Playlist::track($client, $index) or return;
    _startCastForUrl($track->url);
}

sub _requestTrackUrl {
    my ($request, @params) = @_;

    for my $param (@params) {
        my $value = $request->getParam($param);
        next unless defined $value;

        if (ref $value && eval { $value->can('url') }) {
            my $url = $value->url || '';
            return $url if _youtubeVideoId($url);
            next;
        }

        if ($param eq 'track_id' && $value =~ /\A\d+(?:,\d+)*\z/) {
            for my $trackId (split /,/, $value) {
                my $track = Slim::Schema->find('Track', $trackId);
                my $url = $track && $track->url;
                return $url if $url && _youtubeVideoId($url);
            }
            next;
        }

        return $value if _youtubeVideoId($value);

        if ($value =~ /\A\d+\z/) {
            my $track = Slim::Schema->find('Track', $value);
            my $url = $track && $track->url;
            return $url if $url && _youtubeVideoId($url);
        }
    }

    return '';
}

sub _startCastForUrl {
    my ($url) = @_;
    return unless $prefs->get('enabled');

    my $host = $prefs->get('target_host') || '';
    $host =~ s/^\s+|\s+$//g;
    unless (length $host) {
        unless ($warnedMissingHost) {
            $log->warn('Automatic YouTube casting is enabled, but no Chromecast host is configured');
            $warnedMissingHost = 1;
        }
        return;
    }
    $warnedMissingHost = 0;
    unless (_validHost($host)) {
        $log->error('Configured Chromecast host is invalid');
        return;
    }

    my $videoId = _youtubeVideoId($url);
    unless ($videoId) {
        $log->debug("Play request is not a YouTube track: $url");
        return;
    }

    my $pluginDir = dirname(__FILE__);
    my $workerOptions = { die_upon_destroy => 0 };
    my $logDir = Slim::Utils::OSDetect::dirsFor('log');
    $workerOptions->{stderr} = catfile($logDir, 'youtubecast-worker.log') if $logDir;

    my $worker = eval {
        require Proc::Background;
        Proc::Background->new(
            $workerOptions,
            $^X,
            '-I',
            $pluginDir,
            catfile($pluginDir, 'cast_worker.pl'),
            $host,
            $videoId,
        );
    };

    if (!$worker || $@) {
        $log->error('Could not start Chromecast worker: ' . ($@ || 'process creation failed'));
        return;
    }

    @workers = grep { $_ && $_->alive } @workers;
    push @workers, $worker;
    $log->info("Started Chromecast YouTube cast for video $videoId");
}

sub _validHost {
    my ($host) = @_;
    return $host =~ /\A[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?\z/;
}

sub _youtubeVideoId {
    my ($url) = @_;

    return $1 if $url =~ m{(?:youtube\.com/(?:watch\?[^#]*?\bv=|embed/|v/|shorts/|live/)|youtu\.be/)([A-Za-z0-9_-]{11})(?:[?&#]|\z)}i;
    return $1 if $url =~ m{\Ayoutube://([A-Za-z0-9_-]{11})(?:[?&]|\z)}i;

    return;
}

1;
