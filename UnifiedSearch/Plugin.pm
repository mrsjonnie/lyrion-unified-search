package Plugins::UnifiedSearch::Plugin;

use strict;
use warnings;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Menu::GlobalSearch;
use Slim::Utils::Log;
use Slim::Utils::PluginManager;
use Slim::Utils::Strings qw(string);

our $VERSION = '0.3.3';

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
    my $items = searchInfoMenu($client, { search => $query });

    $callback->({ items => $items || [] });
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
        _artistResultsCallback($callback, string('PLUGIN_UNIFIEDSEARCH_LOCAL')),
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
        _artistResultsCallback($callback, string('PLUGIN_UNIFIEDSEARCH_YOUTUBE')),
        \%search_args,
        { type => 'channel' },
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
        _artistResultsCallback($callback, string('PLUGIN_UNIFIEDSEARCH_SPOTTY')),
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
        _artistResultsCallback($callback, string('PLUGIN_UNIFIEDSEARCH_SPOTON')),
        \%search_args,
        { query => $query, type => 'artist' },
    );
}

sub _artistResultsCallback {
    my ($callback, $name) = @_;

    return sub {
        my ($feed) = @_;
        $feed = {} unless ref $feed eq 'HASH';
        my @items = ref $feed->{items} eq 'ARRAY' ? @{ $feed->{items} } : ();
        splice @items, 3 if @items > 3;

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
