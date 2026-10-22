package Plugins::UnifiedSearch::Plugin;

use strict;
use warnings;
use base qw(Slim::Plugin::Base);

use URI::Escape qw(uri_escape_utf8);
use Slim::Menu::GlobalSearch;
use Slim::Utils::Log;

our $VERSION = '0.1.6';

my $log = Slim::Utils::Log->addLogCategory({
    category     => 'plugin.unifiedsearch',
    defaultLevel => 'WARN',
    description  => 'Lyrion Unified Search',
});

sub initPlugin {
    my $class = shift;

    Slim::Menu::GlobalSearch->registerInfoProvider(
        unifiedsearch => (
            after => 'middle',
            func  => \&searchInfoMenu,
        )
    );

    $log->info('Registered Global Search provider');
}

sub getDisplayName {
    return 'Lyrion Unified Search';
}

sub searchInfoMenu {
    my ($client, $tags) = @_;
    my $query = $tags->{search} // '';
    return unless length $query;

    my @items;
    my $escaped = uri_escape_utf8($query);

    push @items, {
        name      => 'Local library',
        type      => 'link',
        url       => 'http://192.168.178.99:9001/search.html?ajaxSearch=1&q=' . $escaped,
        cachetime => 0,
    };

    # Resolve SpotOn directly rather than silently skipping it based on
    # PluginManager state. Log the reason if its callback is unavailable.
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

    $log->debug('Global Search query handled; returning ' . scalar(@items) . ' item(s)');
    return @items ? \@items : undef;
}

sub shutdownPlugin {
    Slim::Menu::GlobalSearch->deregisterInfoProvider('unifiedsearch');
}

1;
