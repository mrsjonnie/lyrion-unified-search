package Plugins::UnifiedSearch::Plugin;

use strict;
use warnings;
use base qw(Slim::Plugin::Base);

use URI::Escape qw(uri_escape_utf8);
use Slim::Menu::GlobalSearch;
use Slim::Utils::PluginManager;

our $VERSION = '0.1.5';

sub initPlugin {
    my $class = shift;

    # Return individual items to Global Search, rather than a nested submenu.
    # Material Skin requests "globalsearch items" and renders these items at
    # the same level as the native YouTube provider.
    Slim::Menu::GlobalSearch->registerInfoProvider(
        unifiedsearch => (
            after => 'middle',
            func  => \&searchInfoMenu,
        )
    );
}

sub getDisplayName {
    # Use a literal fallback so the plugin remains readable even if strings.txt
    # has not yet been loaded by the server's plugin manager.
    return 'Lyrion Unified Search';
}

sub searchInfoMenu {
    my ($client, $tags) = @_;
    my $query = $tags->{search} // '';
    return unless length $query;

    my @items;

    # Local library search uses the LMS web search page on this installation.
    my $escaped = uri_escape_utf8($query);
    push @items, {
        name      => 'Local library',
        type      => 'link',
        url       => 'http://192.168.178.99:9001/search.html?ajaxSearch=1&q=' . $escaped,
        cachetime => 0,
    };

    # SpotOn exposes its existing search feed through this callback. Its
    # passthrough shape is the same one used by SpotOn's own recent-search menu.
    if (Slim::Utils::PluginManager->isEnabled('Plugins::SpotOn::Plugin')) {
        my $ok = eval { require Plugins::SpotOn::Plugin; 1 };
        if ($ok && Plugins::SpotOn::Plugin->can('_searchFromHistoryFeed')) {
            push @items, {
                name        => 'Spotify (SpotOn)',
                type        => 'link',
                url         => \&Plugins::SpotOn::Plugin::_searchFromHistoryFeed,
                passthrough => [{ query => $query }],
                cachetime   => 0,
            };
        }
    }

    # Returning an arrayref makes the entries visible directly in the
    # Global Search result list. YouTube already registers its own provider.
    return @items ? \@items : undef;
}

sub shutdownPlugin {
    Slim::Menu::GlobalSearch->deregisterInfoProvider('unifiedsearch');
}

1;
