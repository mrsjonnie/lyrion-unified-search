package Plugins::UnifiedSearch::Plugin;

use strict;
use warnings;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Menu::GlobalSearch;
use Slim::Utils::Log;
use Slim::Utils::PluginManager;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);
use JSON::XS qw(encode_json decode_json);
use URI::Escape qw(uri_escape_utf8);

our $VERSION = '0.3.12';

my $enabled = 0;

my $log = Slim::Utils::Log->addLogCategory({
    category     => 'plugin.unifiedsearch',
    defaultLevel => 'WARN',
    description  => 'Lyrion Unified Search',
});

sub initPlugin {
    my $class = shift;
    $enabled = 0;

    my $registered = eval {
        Slim::Menu::GlobalSearch->registerInfoProvider(
            unifiedsearch => (
                isa   => 'middle',
                func  => \&searchInfoMenu,
            )
        );
        1;
    };

    if (!$registered) {
        $log->error('UnifiedSearch could not register Global Search provider: ' . ($@ || 'unknown error'));
        return;
    }

    $enabled = 1;

    if (main::WEBUI) {
        require Slim::Web::Pages;
        Slim::Web::Pages->addPageFunction('plugins/UnifiedSearch/search.html', sub {
            return \'' unless $enabled;

            my ($client, $params) = @_;
            return Slim::Web::HTTP::filltemplatefile('plugins/UnifiedSearch/search.html', $params);
        });
        Slim::Web::Pages->addPageFunction('plugins/UnifiedSearch/results.json', \&searchResultsHandler);
        Slim::Web::Pages->addPageLinks('browse', {
            'PLUGIN_UNIFIEDSEARCH' => 'plugins/UnifiedSearch/search.html',
        });

    }

    $class->SUPER::initPlugin(
        feed   => \&applicationFeed,
        tag    => 'unifiedsearch',
        is_app => 1,
        type   => 'link',
        weight => 100,
    );

    if (main::WEBUI) {
        Slim::Web::Pages->addPageFunction('plugins/unifiedsearch/index.html', sub {
            return \'' unless $enabled;

            my ($client, $params) = @_;
            return Slim::Web::HTTP::filltemplatefile('plugins/UnifiedSearch/search.html', $params);
        });
    }

    $log->debug('UnifiedSearch registered Global Search provider');
}

sub applicationFeed {
    my ($client, $callback) = @_;
    $callback->({
        items => $enabled ? [{
            name => string('PLUGIN_UNIFIEDSEARCH'),
            icon => 'html/images/search.png',
            type => 'search',
            url  => \&applicationSearchFeed,
        }] : [],
    });
}

sub applicationSearchFeed {
    my ($client, $callback, $args) = @_;
    return $callback->({ items => [] }) unless $enabled;

    my $query = $args && $args->{search} // '';
    return $callback->({ items => [] }) unless length $query;

    _searchTopArtists($client, $query, undef, sub {
        my ($sources) = @_;
        my @items;

        for my $source (qw(local youtube spotty spoton deezer qobuz bbcsounds radionet podcast)) {
            my $result = $sources->{$source};
            next unless $result;
            for my $hit (@{ $result->{items} || [] }) {
                next unless ref $hit eq 'HASH';
                my $name = _itemName($hit);
                next unless length $name;

                my %item = %$hit;
                $item{name} = $source eq 'bbcsounds'
                    ? 'BBC: ' . $name
                    : $result->{name} . ': ' . $name;
                push @items, \%item;
            }
        }

        $callback->({ items => \@items });
    });
}

sub searchResultsHandler {
    my ($client, $params, $callback, $httpClient, $response) = @_;
    $response->content_type('application/json; charset=utf-8');

    my $query = $params->{search} // '';
    if (!$enabled || !length $query) {
        my $json = encode_json({ sources => {} });
        return $callback->($client, $params, \$json, $httpClient, $response);
    }

    _searchTopArtists($client, $query, $params->{source}, sub {
        my ($sources) = @_;
        my %formatted;
        for my $source (keys %$sources) {
            $formatted{$source} = {
                name  => $sources->{$source}{name},
                error => $sources->{$source}{error},
                items => [
                    map {
                        _itemName($_, $source eq 'bbcsounds' ? 'BBC: ' : '')
                    } @{ $sources->{$source}{items} || [] }
                ],
            };
        }
        my $json = encode_json({ sources => \%formatted });
        $callback->($client, $params, \$json, $httpClient, $response);
    });
}

sub _searchTopArtists {
    my ($client, $query, $source_filter, $callback) = @_;
    my @searches = ({
        key         => 'local',
        name        => string('PLUGIN_UNIFIEDSEARCH_LOCAL'),
        handler     => \&localSearchFeed,
        passthrough => { query => $query },
    });

    if (Slim::Utils::PluginManager->isEnabled('Plugins::YouTube::Plugin')) {
        my $loaded = eval { require Plugins::YouTube::Plugin; 1 };
        if ($loaded && Plugins::YouTube::Plugin->can('searchHandler')) {
            push @searches, {
                key         => 'youtube',
                name        => string('PLUGIN_UNIFIEDSEARCH_YOUTUBE'),
                handler     => \&youtubeSearchFeed,
                passthrough => { query => $query },
            };
        }
        elsif (!$loaded) {
            $log->warn('YouTube live search unavailable: ' . ($@ || 'could not load plugin'));
        }
    }

    if (Slim::Utils::PluginManager->isEnabled('Plugins::Spotty::Plugin')) {
        my $loaded = eval { require Plugins::Spotty::OPML; 1 };
        if ($loaded && Plugins::Spotty::OPML->can('search')) {
            push @searches, {
                key         => 'spotty',
                name        => string('PLUGIN_UNIFIEDSEARCH_SPOTTY'),
                handler     => \&spottySearchFeed,
                passthrough => { query => $query },
            };
        }
        elsif (!$loaded) {
            $log->warn('Spotty live search unavailable: ' . ($@ || 'could not load plugin'));
        }
    }

    if (Slim::Utils::PluginManager->isEnabled('Plugins::SpotOn::Plugin')) {
        my $loaded = eval { require Plugins::SpotOn::Plugin; 1 };
        if ($loaded && Plugins::SpotOn::Plugin->can('_searchTypeFeed')) {
            push @searches, {
                key         => 'spoton',
                name        => string('PLUGIN_UNIFIEDSEARCH_SPOTON'),
                handler     => \&spotonSearchFeed,
                passthrough => { query => $query },
            };
        }
        elsif (!$loaded) {
            $log->warn('SpotOn live search unavailable: ' . ($@ || 'could not load plugin'));
        }
    }

    if (Slim::Utils::PluginManager->isEnabled('Plugins::Deezer::Plugin')) {
        my $loaded = eval { require Plugins::Deezer::Plugin; 1 };
        if ($loaded && Plugins::Deezer::Plugin->can('search')) {
            push @searches, {
                key         => 'deezer',
                name        => string('PLUGIN_UNIFIEDSEARCH_DEEZER'),
                handler     => \&deezerSearchFeed,
                passthrough => { query => $query },
            };
        }
        elsif (!$loaded) {
            $log->warn('Deezer live search unavailable: ' . ($@ || 'could not load plugin'));
        }
    }

    if (Slim::Utils::PluginManager->isEnabled('Plugins::Qobuz::Plugin')) {
        my $loaded = eval { require Plugins::Qobuz::Plugin; 1 };
        if ($loaded && Plugins::Qobuz::Plugin->can('QobuzSearch')) {
            push @searches, {
                key         => 'qobuz',
                name        => string('PLUGIN_UNIFIEDSEARCH_QOBUZ'),
                handler     => \&qobuzSearchFeed,
                passthrough => { query => $query },
            };
        }
        elsif (!$loaded) {
            $log->warn('Qobuz live search unavailable: ' . ($@ || 'could not load plugin'));
        }
    }

    if (_bbcSoundsAvailable()) {
        push @searches, {
            key         => 'bbcsounds',
            name        => string('PLUGIN_UNIFIEDSEARCH_BBCSOUNDS'),
            handler     => \&bbcSoundsSearchFeed,
            passthrough => { query => $query },
        };
    }

    if (Slim::Utils::PluginManager->isEnabled('Slim::Plugin::Podcast::Plugin')) {
        my $loaded = eval { require Slim::Plugin::Podcast::Plugin; 1 };
        if ($loaded && Slim::Plugin::Podcast::Plugin->can('searchHandler')) {
            push @searches, {
                key         => 'podcast',
                name        => string('PLUGIN_UNIFIEDSEARCH_PODCAST'),
                handler     => \&podcastSearchFeed,
                passthrough => { query => $query },
            };
        }
        elsif (!$loaded) {
            $log->warn('Podcast live search unavailable: ' . ($@ || 'could not load plugin'));
        }
    }

    push @searches, {
        key     => 'radionet',
        name    => string('PLUGIN_UNIFIEDSEARCH_RADIONET'),
        handler => \&radionetSearchFeed,
    };

    @searches = grep { $_->{key} eq $source_filter } @searches if $source_filter;
    if (!@searches) {
        $callback->({});
        return;
    }

    my %sources;
    my $remaining = scalar @searches;
    my $responded = 0;
    my $finish = sub {
        return if $responded;
        $remaining--;
        return if $remaining;
        $responded = 1;
        $callback->(\%sources);
    };

    for my $search (@searches) {
        my $completed = 0;
        my $source_callback = sub {
            return if $completed;
            $completed = 1;
            my ($feed) = @_;
            my @items = ref $feed eq 'HASH' && ref $feed->{items} eq 'ARRAY'
                ? @{ $feed->{items} }
                : ();
            $sources{ $search->{key} } = {
                name  => $search->{name},
                items => \@items,
                error => ref $feed eq 'HASH' && $feed->{search_error} ? 1 : 0,
            };
            $finish->();
        };

        my $ok = eval {
            $search->{handler}->(
                $client,
                _resultsCallback($source_callback, $search->{name}, 3),
                { search => $query, quantity => 3 },
                $search->{passthrough},
            );
            1;
        };
        if (!$ok) {
            $log->warn('Live search failed for ' . $search->{key} . ': ' . ($@ || 'unknown error'));
            $source_callback->({ search_error => 1 });
        }
    }
}

sub _itemName {
    my ($item, $prefix) = @_;
    return '' unless ref $item eq 'HASH';
    my $name = $item->{name} || $item->{artist} || $item->{album} || $item->{title} || $item->{channel} || '';
    return length($name) ? ($prefix || '') . $name : '';
}

sub getDisplayName {
    return 'Lyrion Unified Search';
}

sub searchInfoMenu {
    my ($client, $tags) = @_;

    my $query = $tags && $tags->{search} // '';
    return unless length $query;

    my @items;

    push @items, {
        name        => string('PLUGIN_UNIFIEDSEARCH_LOCAL'),
        icon        => 'html/images/search.png',
        type        => 'link',
        url         => \&localSearchFeed,
        passthrough => [{ query => $query }],
        cachetime   => 0,
    };

    if (Slim::Utils::PluginManager->isEnabled('Plugins::YouTube::Plugin')) {
        my $loaded = eval { require Plugins::YouTube::Plugin; 1 };
        if (!$loaded) {
            $log->warn('YouTube search unavailable: could not load plugin: ' . ($@ || 'unknown error'));
        }
        elsif (Plugins::YouTube::Plugin->can('searchHandler')) {
            push @items, {
                name        => string('PLUGIN_UNIFIEDSEARCH_YOUTUBE'),
                icon        => 'html/images/search.png',
                type        => 'link',
                url         => \&youtubeSearchFeed,
                passthrough => [{ query => $query }],
                cachetime   => 0,
            };
        }
        else {
            $log->warn('YouTube search unavailable: searchHandler callback not found');
        }
    }

    if (Slim::Utils::PluginManager->isEnabled('Plugins::Spotty::Plugin')) {
        my $loaded = eval { require Plugins::Spotty::OPML; 1 };
        if (!$loaded) {
            $log->warn('Spotty search unavailable: could not load plugin: ' . ($@ || 'unknown error'));
        }
        elsif (Plugins::Spotty::OPML->can('search')) {
            push @items, {
                name        => string('PLUGIN_UNIFIEDSEARCH_SPOTTY'),
                icon        => 'html/images/search.png',
                type        => 'link',
                url         => \&spottySearchFeed,
                passthrough => [{ query => $query }],
                cachetime   => 0,
            };
        }
        else {
            $log->warn('Spotty artist search unavailable: search callback not found');
        }
    }

    if (Slim::Utils::PluginManager->isEnabled('Plugins::SpotOn::Plugin')) {
        my $loaded = eval { require Plugins::SpotOn::Plugin; 1 };
        if (!$loaded) {
            $log->warn('SpotOn search unavailable: could not load plugin: ' . ($@ || 'unknown error'));
        }
        elsif (Plugins::SpotOn::Plugin->can('_searchTypeFeed')) {
            push @items, {
                name        => string('PLUGIN_UNIFIEDSEARCH_SPOTON'),
                icon        => 'html/images/search.png',
                type        => 'link',
                url         => \&spotonSearchFeed,
                passthrough => [{ query => $query }],
                cachetime   => 0,
            };
        }
        else {
            $log->warn('SpotOn artist search unavailable: _searchTypeFeed callback not found');
        }
    }

    if (Slim::Utils::PluginManager->isEnabled('Plugins::Deezer::Plugin')) {
        my $loaded = eval { require Plugins::Deezer::Plugin; 1 };
        if (!$loaded) {
            $log->warn('Deezer search unavailable: could not load plugin: ' . ($@ || 'unknown error'));
        }
        elsif (Plugins::Deezer::Plugin->can('search')) {
            push @items, {
                name        => string('PLUGIN_UNIFIEDSEARCH_DEEZER'),
                icon        => 'html/images/search.png',
                type        => 'link',
                url         => \&deezerSearchFeed,
                passthrough => [{ query => $query }],
                cachetime   => 0,
            };
        }
        else {
            $log->warn('Deezer artist search unavailable: search callback not found');
        }
    }

    if (Slim::Utils::PluginManager->isEnabled('Plugins::Qobuz::Plugin')) {
        my $loaded = eval { require Plugins::Qobuz::Plugin; 1 };
        if (!$loaded) {
            $log->warn('Qobuz search unavailable: could not load plugin: ' . ($@ || 'unknown error'));
        }
        elsif (Plugins::Qobuz::Plugin->can('QobuzSearch')) {
            push @items, {
                name        => string('PLUGIN_UNIFIEDSEARCH_QOBUZ'),
                icon        => 'html/images/search.png',
                type        => 'link',
                url         => \&qobuzSearchFeed,
                passthrough => [{ query => $query }],
                cachetime   => 0,
            };
        }
        else {
            $log->warn('Qobuz artist search unavailable: QobuzSearch callback not found');
        }
    }

    if (_bbcSoundsAvailable()) {
        push @items, {
            name        => string('PLUGIN_UNIFIEDSEARCH_BBCSOUNDS'),
            icon        => 'html/images/search.png',
            type        => 'link',
            url         => \&bbcSoundsSearchFeed,
            passthrough => [{ query => $query }],
            cachetime   => 0,
        };
    }

    if (Slim::Utils::PluginManager->isEnabled('Slim::Plugin::Podcast::Plugin')) {
        my $loaded = eval { require Slim::Plugin::Podcast::Plugin; 1 };
        if (!$loaded) {
            $log->warn('Podcast search unavailable: could not load plugin: ' . ($@ || 'unknown error'));
        }
        elsif (Slim::Plugin::Podcast::Plugin->can('searchHandler')) {
            push @items, {
                name        => string('PLUGIN_UNIFIEDSEARCH_PODCAST'),
                icon        => 'html/images/search.png',
                type        => 'link',
                url         => \&podcastSearchFeed,
                passthrough => [{ query => $query }],
                cachetime   => 0,
            };
        }
        else {
            $log->warn('Podcast search unavailable: searchHandler callback not found');
        }
    }

    push @items, {
        name        => string('PLUGIN_UNIFIEDSEARCH_RADIONET'),
        icon        => 'html/images/search.png',
        type        => 'link',
        url         => \&radionetSearchFeed,
        passthrough => [{ query => $query }],
        cachetime   => 0,
    };

    $log->debug('UnifiedSearch returning ' . scalar(@items) . ' search item(s)');
    return @items ? \@items : undef;
}

sub localSearchFeed {
    my ($client, $callback, $args, $passthrough) = @_;
    my $query = $passthrough && $passthrough->{query} // '';
    require Slim::Menu::BrowseLibrary;

    my %search_args = $args ? %{$args} : ();
    $search_args{search} = $query;
    $search_args{quantity} = 3;

    Slim::Menu::BrowseLibrary::_artists(
        $client,
        _resultsCallback($callback, string('PLUGIN_UNIFIEDSEARCH_LOCAL'), 3),
        \%search_args,
        {},
    );
}

sub youtubeSearchFeed {
    my ($client, $callback, $args, $passthrough) = @_;
    my $query = $passthrough && $passthrough->{query} // '';
    my %search_args = $args ? %{$args} : ();
    $search_args{search} = $query;
    $search_args{quantity} = 3;

    Plugins::YouTube::Plugin::searchHandler(
        $client,
        _resultsCallback($callback, string('PLUGIN_UNIFIEDSEARCH_YOUTUBE'), 3),
        \%search_args,
        { type => 'video' },
    );
}

sub spottySearchFeed {
    my ($client, $callback, $args, $passthrough) = @_;
    my $query = $passthrough && $passthrough->{query} // '';
    my %search_args = $args ? %{$args} : ();
    $search_args{search} = $query;
    $search_args{quantity} = 3;

    Plugins::Spotty::OPML::search(
        $client,
        _resultsCallback($callback, string('PLUGIN_UNIFIEDSEARCH_SPOTTY'), 3),
        \%search_args,
        { type => 'artist' },
    );
}

sub spotonSearchFeed {
    my ($client, $callback, $args, $passthrough) = @_;
    my $query = $passthrough && $passthrough->{query} // '';
    my %search_args = $args ? %{$args} : ();
    $search_args{quantity} = 3;

    Plugins::SpotOn::Plugin::_searchTypeFeed(
        $client,
        _resultsCallback($callback, string('PLUGIN_UNIFIEDSEARCH_SPOTON'), 3),
        \%search_args,
        { query => $query, type => 'artist' },
    );
}

sub deezerSearchFeed {
    my ($client, $callback, $args, $passthrough) = @_;
    my $query = $passthrough && $passthrough->{query} // '';
    my %search_args = $args ? %{$args} : ();
    $search_args{search} = $query;
    $search_args{quantity} = 3;

    Plugins::Deezer::Plugin::search(
        $client,
        _resultsCallback($callback, string('PLUGIN_UNIFIEDSEARCH_DEEZER'), 3),
        \%search_args,
        { type => 'artist' },
    );
}

sub qobuzSearchFeed {
    my ($client, $callback, $args, $passthrough) = @_;
    my $query = $passthrough && $passthrough->{query} // '';
    my %search_args = $args ? %{$args} : ();
    $search_args{quantity} = 3;

    Plugins::Qobuz::Plugin::QobuzSearch(
        $client,
        _resultsCallback($callback, string('PLUGIN_UNIFIEDSEARCH_QOBUZ'), 3),
        \%search_args,
        { q => $query, type => 'artists' },
    );
}

sub _bbcSoundsAvailable {
    return 0 unless Slim::Utils::PluginManager->isEnabled('Plugins::BBCSounds::Plugin');

    my $loaded = eval { require Plugins::BBCSounds::BBCSoundsFeeder; 1 };
    unless ($loaded) {
        $log->warn('BBC Sounds search unavailable: ' . ($@ || 'could not load plugin'));
        return 0;
    }

    unless (Plugins::BBCSounds::BBCSoundsFeeder->can('getPage')) {
        $log->warn('BBC Sounds search unavailable: getPage callback not found');
        return 0;
    }

    return 1;
}

sub bbcSoundsSearchFeed {
    my ($client, $callback, $args, $passthrough) = @_;
    my $query = $passthrough && $passthrough->{query} // '';
    my %search_args = $args ? %{$args} : ();
    $search_args{search} = $query;

    my $result_callback = _resultsCallback(
        $callback,
        string('PLUGIN_UNIFIEDSEARCH_BBCSOUNDS'),
        3,
    );
    my $feed_callback = sub {
        my ($feed) = @_;
        unless (ref $feed eq 'HASH') {
            $log->warn('BBC Sounds search returned an invalid feed');
            return $callback->({ items => [], search_error => 1 });
        }

        my $feed_items = ref $feed->{items} eq 'ARRAY' ? $feed->{items} : [];
        my @items = map {
            ref $_ eq 'HASH'
                ? { %$_, name => _itemName($_, 'BBC: ') }
                : $_
        } @$feed_items;
        $feed = { %$feed, items => \@items };
        $result_callback->($feed);
    };

    Plugins::BBCSounds::BBCSoundsFeeder::getPage(
        $client,
        $feed_callback,
        \%search_args,
        { type => 'searchall', query => $query },
    );
}

sub podcastSearchFeed {
    my ($client, $callback, $args, $passthrough) = @_;
    my $query = $passthrough && $passthrough->{query} // '';
    my $provider = Slim::Plugin::Podcast::Plugin::getProviderByName();
    my ($search_item) = grep {
        ref $_ eq 'HASH' && (!$_->{type} || $_->{type} eq 'search') && !$_->{enclosure}
    } @{ $provider->getMenuItems($client) || [] };

    unless ($search_item) {
        $log->warn('Podcast live search unavailable: selected provider has no search item');
        return $callback->({ items => [], search_error => 1 });
    }

    my %search_args = $args ? %{$args} : ();
    $search_args{search} = $query;
    $search_args{quantity} = 3;

    Slim::Plugin::Podcast::Plugin::searchHandler(
        $client,
        _resultsCallback($callback, string('PLUGIN_UNIFIEDSEARCH_PODCAST'), 3),
        \%search_args,
        { provider => $provider, item => $search_item },
    );
}

sub radionetSearchFeed {
    my ($client, $callback, $args, $passthrough) = @_;
    my $query = $passthrough && $passthrough->{query};
    $query = $args->{search} if !defined $query && $args;
    $query ||= '';
    my $language = lc(preferences('server')->get('language') || 'en');
    $language = 'en' unless $language =~ /\A[a-z]{2}\z/;
    my $url = 'https://prod.radio-api.net/stations/search?query='
        . uri_escape_utf8($query) . '&language=' . $language;

    require Slim::Networking::SimpleAsyncHTTP;
    Slim::Networking::SimpleAsyncHTTP->new(
        sub {
            my $response = shift;
            my $result = eval { decode_json($response->content) };
            if ($@ || ref $result ne 'HASH') {
                $log->warn('Radio.net search returned invalid JSON: ' . ($@ || 'unexpected response'));
                return $callback->({ items => [], search_error => 1 });
            }

            my @items;
            my $playables = $result->{playables};
            for my $station (ref $playables eq 'ARRAY' ? @$playables : ()) {
                next unless ref $station eq 'HASH' && ($station->{type} || '') eq 'STATION';
                my $streams = $station->{streams};
                my @streams = ref $streams eq 'ARRAY' ? @$streams
                    : ref $streams eq 'HASH' ? ($streams)
                    : ();
                my ($stream) = grep {
                    ref $_ eq 'HASH'
                        && ($_->{status} || '') eq 'VALID'
                        && ($_->{url} || '') =~ m{\Ahttps?://}i
                } @streams;
                next unless $stream;

                my @details = grep { defined && length } (
                    $station->{city},
                    $station->{country},
                    ref $station->{genres} eq 'ARRAY' ? join(', ', @{ $station->{genres} }) : '',
                );
                next unless defined $station->{name} && length $station->{name};
                push @items, {
                    type        => 'audio',
                    name        => $station->{name},
                    url         => $stream->{url},
                    image       => $station->{logo175x175} || $station->{logo100x100} || '',
                    description => join(', ', @details),
                };
                last if @items == 3;
            }

            $callback->({
                name  => string('PLUGIN_UNIFIEDSEARCH_RADIONET'),
                items => \@items,
            });
        },
        sub {
            $log->warn('Radio.net station search failed: ' . ($_[1] || 'unknown network error'));
            $callback->({ items => [], search_error => 1 });
        },
        { cache => 1, expires => 600 },
    )->get($url);
}

sub _resultsCallback {
    my ($callback, $name, $limit) = @_;

    return sub {
        my ($feed) = @_;
        $feed = {} unless ref $feed eq 'HASH';
        my @items = ref $feed->{items} eq 'ARRAY' ? @{ $feed->{items} } : ();
        splice @items, $limit if defined $limit && @items > $limit;

        $callback->({
            %$feed,
            name  => $name,
            icon  => 'html/images/search.png',
            items => \@items,
        });
    };
}

sub shutdownPlugin {
    $enabled = 0;
    Slim::Menu::GlobalSearch->deregisterInfoProvider('unifiedsearch');
    if (main::WEBUI) {
        Slim::Web::Pages->delPageLinks('browse', 'PLUGIN_UNIFIEDSEARCH');
        Slim::Web::Pages->delPageLinks('apps', 'PLUGIN_UNIFIEDSEARCH');
    }

    my $apps = Slim::Plugin::Base->nonSNApps();
    @$apps = grep { $_ ne __PACKAGE__ } @$apps if $apps;
}

1;
