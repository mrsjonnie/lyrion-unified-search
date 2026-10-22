package Plugins::UnifiedSearch::Plugin;

use strict;
use warnings;
use base qw(Slim::Plugin::Base);

use URI::Escape qw(uri_escape_utf8);
use Slim::Menu::BrowseLibrary;
use Slim::Utils::Log;

our $VERSION = '0.1.8';

my $log = Slim::Utils::Log->addLogCategory({
    category     => 'plugin.unifiedsearch',
    defaultLevel => 'WARN',
    description  => 'Lyrion Unified Search',
});

sub initPlugin {
    my $class = shift;

    # Register a standalone search entry in LMS's Browse Library menu.
    # This avoids patching Material Skin's client-side Global Search allowlist.
    my $registered = eval {
        Slim::Menu::BrowseLibrary->registerNode({
            type   => 'search',
            name   => 'Unified Search',
            id     => 'unifiedSearchCombined',
            params => { mode => 'unifiedSearchCombined' },
            feed   => \&searchFeed,
            icon   => 'html/images/search.png',
            weight => 89,
            cache  => 0,
        });
        1;
    };

    if (!$registered) {
        $log->error('Unified Search could not register Browse Library entry: ' . ($@ || 'unknown error'));
        return;
    }

    $log->info("Unified Search v$VERSION registered");
}

sub getDisplayName {
    return 'Lyrion Unified Search';
}

# The user enters one query here. We return one result per existing provider;
# choosing a provider is the single extra click before its native results open.
sub searchFeed {
    my ($client, $callback, $args, $passthrough) = @_;

    my $query = $args->{search} // '';
    $query = $passthrough->{search} // $query if ref($passthrough) eq 'HASH';
    my @items;

    if (length $query) {
        my $escaped = uri_escape_utf8($query);

        push @items, {
            name      => 'Local library (LMS)',
            type      => 'link',
            url       => '/search.html?ajaxSearch=1&q=' . $escaped,
            cachetime => 0,
        };

        my $youtube_loaded = eval { require Plugins::YouTube::Plugin; 1 };
        if ($youtube_loaded && Plugins::YouTube::Plugin->can('searchHandler')) {
            push @items, {
                name        => 'YouTube',
                type        => 'link',
                url         => \&Plugins::YouTube::Plugin::searchHandler,
                passthrough => [{ q => $query }],
                cachetime   => 0,
            };
        }
        else {
            $log->debug('YouTube search is unavailable; plugin not loaded or handler missing');
        }

        my $spoton_loaded = eval { require Plugins::SpotOn::Plugin; 1 };
        if ($spoton_loaded && Plugins::SpotOn::Plugin->can('_searchFromHistoryFeed')) {
            push @items, {
                name        => 'Spotify (SpotOn)',
                type        => 'link',
                url         => \&Plugins::SpotOn::Plugin::_searchFromHistoryFeed,
                passthrough => [{ query => $query }],
                cachetime   => 0,
            };
        }
        else {
            $log->debug('SpotOn search is unavailable; plugin not loaded or callback missing');
        }
    }

    $callback->({
        name  => 'Unified Search',
        items => \@items,
    });
}

sub shutdownPlugin {
    Slim::Menu::BrowseLibrary->deregisterNode('unifiedSearchCombined');
}

1;
