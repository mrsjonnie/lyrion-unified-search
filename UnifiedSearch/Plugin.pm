package Plugins::UnifiedSearch::Plugin;

use strict;
use warnings;
use base qw(Slim::Plugin::Base);

use URI::Escape qw(uri_escape_utf8);
use Slim::Utils::Strings qw(cstring);
use Slim::Menu::GlobalSearch;
use Slim::Utils::PluginManager;

our $VERSION = '0.1.3';

sub initPlugin {
    my $class = shift;

    # LMS Global Search is the supported extension point for third-party search
    # providers. We add one grouped entry and leave all existing providers intact.
    Slim::Menu::GlobalSearch->registerInfoProvider(
        unifiedsearch => (
            after => 'middle',
            name  => 'PLUGIN_UNIFIEDSEARCH',
            func  => \&searchInfoMenu,
        )
    );
}

sub getDisplayName {
    return 'PLUGIN_UNIFIEDSEARCH';
}

sub searchInfoMenu {
    my ($client, $tags) = @_;
    my $query = $tags->{search} // '';
    return unless length $query;

    my @items;

    # Keep the local-library destination on the user's LMS host. The query is
    # escaped as a URL component; no Default or Material Skin files are changed.
    my $escaped = uri_escape_utf8($query);
    push @items, {
        name => cstring($client, 'PLUGIN_UNIFIEDSEARCH_LOCAL'),
        type => 'link',
        url  => 'http://192.168.178.99:9001/search.html?ajaxSearch=1&q=' . $escaped,
    };

    # YouTube already exposes a GlobalSearch provider. This entry makes the
    # direct search action available from the same Unified Search group.
    if (Slim::Utils::PluginManager->isEnabled('Plugins::YouTube::Plugin')) {
        my $ok = eval { require Plugins::YouTube::Plugin; 1 };
        if ($ok && Plugins::YouTube::Plugin->can('searchHandler')) {
            push @items, {
                name        => cstring($client, 'PLUGIN_UNIFIEDSEARCH_YOUTUBE'),
                type        => 'link',
                url         => \&Plugins::YouTube::Plugin::searchHandler,
                passthrough => [{ q => $query }],
                cachetime   => 0,
            };
        }
    }

    # SpotOn intentionally has no GlobalSearch provider of its own. Reuse its
    # existing search feed through its history-replay shim, which accepts query
    # as passthrough and does not add a duplicate history entry.
    if (Slim::Utils::PluginManager->isEnabled('Plugins::SpotOn::Plugin')) {
        my $ok = eval { require Plugins::SpotOn::Plugin; 1 };
        if ($ok && Plugins::SpotOn::Plugin->can('_searchFromHistoryFeed')) {
            push @items, {
                name        => cstring($client, 'PLUGIN_UNIFIEDSEARCH_SPOTON'),
                type        => 'link',
                url         => \&Plugins::SpotOn::Plugin::_searchFromHistoryFeed,
                passthrough => [{ query => $query }],
                cachetime   => 0,
            };
        }
    }

    return unless @items;

    return {
        name  => cstring($client, 'PLUGIN_UNIFIEDSEARCH'),
        items => \@items,
    };
}

sub shutdownPlugin {
    Slim::Menu::GlobalSearch->deregisterInfoProvider('unifiedsearch');
}

1;
