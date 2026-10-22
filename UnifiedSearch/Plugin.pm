package Plugins::UnifiedSearch::Plugin;

use strict;
use warnings;
use base qw(Slim::Plugin::Base);

use URI::Escape qw(uri_escape_utf8);
use Slim::Menu::BrowseLibrary;
use Slim::Menu::GlobalSearch;
use Slim::Utils::Log;
use Slim::Utils::Network;

our $VERSION = '0.2.0';

my $enabled = 0;

my $log = Slim::Utils::Log->addLogCategory({
    category     => 'plugin.unifiedsearch',
    defaultLevel => 'WARN',
    description  => 'Lyrion Unified Search',
});

sub initPlugin {
    my $class = shift;
    $enabled = 1;

    # Keep these messages at WARN temporarily so they are visible with the
    # default LMS logging level. They confirm whether LMS loads this module.
    $log->warn("UnifiedSearch v$VERSION initPlugin called");

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

        my $modeRegistered = Slim::Menu::BrowseLibrary->registerNode({
            type   => 'link',
            name   => 'PLUGIN_UNIFIEDSEARCH',
            id     => 'myMusicUnifiedSearch',
            params => { mode => 'unifiedsearch' },
            feed   => \&unifiedSearchMode,
            weight => 100,
        });
        $log->error('UnifiedSearch could not register Material Applications menu entry')
            unless $modeRegistered;
    }

    $log->warn('UnifiedSearch registered Global Search provider');
}

sub unifiedSearchMode {
    my ($client, $callback) = @_;

    $callback->({
        items => [{
            name => 'PLUGIN_UNIFIEDSEARCH',
            type => 'link',
            url  => Slim::Utils::Network::serverURL() . '/Default/plugins/UnifiedSearch/search.html',
        }],
    });
}

sub getDisplayName {
    return 'Lyrion Unified Search';
}

sub searchInfoMenu {
    my ($client, $tags) = @_;

    $log->warn('UnifiedSearch searchInfoMenu called');

    my $query = $tags->{search} // '';
    return unless length $query;

    my @items;
    my $escaped = uri_escape_utf8($query);

    push @items, {
        name      => 'Local library',
        type      => 'link',
        url       => Slim::Utils::Network::serverURL() . '/search.html?ajaxSearch=1&q=' . $escaped,
        cachetime => 0,
    };

    # SpotOn is optional. Keep the local-library result even if SpotOn
    # cannot be loaded or its search callback is unavailable.
    my $loaded = eval { require Plugins::SpotOn::Plugin; 1 };
    if (!$loaded) {
        $log->warn('SpotOn search unavailable: could not load plugin: ' . ($@ || 'unknown error'));
    }
    elsif (Plugins::SpotOn::Plugin->can('_searchFromHistoryFeed')) {
        push @items, {
            name        => 'Spotify (SpotOn)',
            type        => 'link',
            url         => \&Plugins::SpotOn::Plugin::_searchFromHistoryFeed,
            passthrough => [{ query => $query }],
            cachetime   => 0,
        };
    }
    else {
        $log->warn('SpotOn search unavailable: _searchFromHistoryFeed callback not found');
    }

    $log->warn('UnifiedSearch returning ' . scalar(@items) . ' search item(s)');
    return @items ? \@items : undef;
}

sub shutdownPlugin {
    $enabled = 0;
    Slim::Menu::GlobalSearch->deregisterInfoProvider('unifiedsearch');
    if (main::WEBUI) {
        Slim::Menu::BrowseLibrary->deregisterNode('myMusicUnifiedSearch');
        Slim::Web::Pages->delPageLinks('browse', 'PLUGIN_UNIFIEDSEARCH');
    }
}

1;
