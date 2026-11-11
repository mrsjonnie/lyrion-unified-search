package Plugins::YouTubeCast::Plugin;

use strict;
use warnings;
use base qw(Slim::Plugin::Base);

use File::Basename qw(dirname);
use File::Spec::Functions qw(catfile);
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
my %lastCast;
my $originalGetNextTrack;
my $hooksInstalled = 0;
my $defaultCastHost = '192.168.178.75';

sub initPlugin {
    my $class = shift;

    $prefs->init({
        host_mappings => '',
    });

    $class->SUPER::initPlugin();

    if (main::WEBUI) {
        require Slim::Web::Pages;
        require Plugins::YouTubeCast::Settings;
        Plugins::YouTubeCast::Settings->new;
    }

    _installYoutubeHooks();
}

sub shutdownPlugin {
    _restoreYoutubeHooks();
    for my $worker (@workers) {
        eval { $worker->die if $worker && $worker->alive };
    }
    @workers = ();
    %lastCast = ();

    my $logDir = eval { Slim::Utils::OSDetect::dirsFor('log') };
    if ($logDir) {
        my $workerLog = catfile($logDir, 'youtubecast-worker.log');
        unlink $workerLog if -f $workerLog;
    }
}

sub getDisplayName {
    return 'PLUGIN_YOUTUBECAST';
}


sub _installYoutubeHooks {
    return if $hooksInstalled;
    my $loaded = eval { require Plugins::YouTube::ProtocolHandler; 1 };
    unless ($loaded && Plugins::YouTube::ProtocolHandler->can('getNextTrack')) {
        $log->warn('Could not load the official YouTube protocol handler; automatic casting is unavailable');
        return;
    }

    no strict 'refs';
    $originalGetNextTrack = \&{'Plugins::YouTube::ProtocolHandler::getNextTrack'};
    $originalNew = \&{'Plugins::YouTube::ProtocolHandler::new'};

    *{'Plugins::YouTube::ProtocolHandler::getNextTrack'} = sub {
        my ($protocolClass, $song, $successCb, $errorCb) = @_;
        my $client = eval { $song->master };
        my $host = _castHostForClient($client);
        return $originalGetNextTrack->(@_)
            unless length($host || '');

        my $videoId = _youtubeVideoId(eval { $song->track->url } || '');
        return $originalGetNextTrack->(@_) unless $videoId;

        my $castSuccess = sub {
            my $config = $song->pluginData('config') || {};
            $config->{format}  = 'mp3';
            $config->{source}  = 'youtubecast';
            $config->{handler} = Plugins::YouTubeCast::SilentHandler->new;
            $config->{sysread} = \&_silentSysread;

            my ($ok, $message) = _startCastForVideoId($client, $videoId);
            $log->warn("Automatic cast failed for $videoId: $message") unless $ok;
            $successCb->();
        };

        return $originalGetNextTrack->($protocolClass, $song, $castSuccess, $errorCb);
    };

    *{'Plugins::YouTube::ProtocolHandler::new'} = sub {
        my ($protocolClass, $args) = @_;
        my $handle = $originalNew->(@_);
        if ($handle && $args && $args->{song}) {
            my $config = eval { $args->{song}->pluginData('config') } || {};
            if (($config->{source} || '') eq 'youtubecast') {
                ${*$handle}{vars}{sessions} ||= [];
            }
        }
        return $handle;
    };

    $hooksInstalled = 1;
    $log->info('Automatic YouTube Cast playback hook installed');
}

sub _restoreYoutubeHooks {
    return unless $hooksInstalled;
    no strict 'refs';
    *{'Plugins::YouTube::ProtocolHandler::getNextTrack'} = $originalGetNextTrack if $originalGetNextTrack;
    *{'Plugins::YouTube::ProtocolHandler::new'} = $originalNew if $originalNew;
    $originalGetNextTrack = undef;
    $originalNew = undef;
    $hooksInstalled = 0;
}

sub _silentSysread {
    my ($vars, $config, $self, $buffer, $length) = @_;
    my $frame = pack('H*', 'fffb9064') . ("\0" x 413);
    my $offset = $vars->{castSilenceOffset} || 0;
    my $stream = $frame x (int(($offset + $length + length($frame) - 1) / length($frame)) + 1);
    my $chunk = substr($stream, $offset, $length);
    $vars->{castSilenceOffset} = $offset + length($chunk);
    $_[3] = $chunk;
    return length($chunk);
}

sub _startCastForVideoId {
    my ($client, $videoId) = @_;
    return (0, 'Invalid YouTube video ID') unless $videoId && $videoId =~ /\A[A-Za-z0-9_-]{11}\z/;

    my $host = _castHostForClient($client) || $defaultCastHost;
    $host =~ s/^\s+|\s+$//g;
    unless (length $host) {
        $log->warn('No Chromecast host is configured for this LMS player');
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
    $log->info("Automatic YouTube video cast requested for $videoId on $playerName ($host)");
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

    return $defaultCastHost;
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


package Plugins::YouTubeCast::SilentHandler;

use strict;
use warnings;

sub new { return bless {}, shift; }
sub flush { return 1; }
sub getStartOffset {
    my ($self, $url, $startTime, $callback) = @_;
    $callback->(0);
}

1;
