package Plugins::UnifiedSearch::Plugin;

use strict;
use warnings;
use base qw(Slim::Plugin::Base);

use URI::Escape qw(uri_escape_utf8);
use Slim::Menu::GlobalSearch;
use Slim::Utils::Log;

our $VERSION = '0.1.7';

my $log = Slim::Utils::Log->addLogCategory({
    category     => 'plugin.unifiedsearch',
    defaultLevel => 'WARN',
    description  => 'Lyrion Unified Search',
});

sub initPlugin {
    my $class = shift;

    # Keep these messages at WARN temporarily so they are visible with the
    # default LMS logging level. They confirm whether LMS loads this module.
    $log->warn("UnifiedSearch v$VERSION initPlugin called");

    my $registered = eval {
        Slim::Menu::GlobalSearch->registerInfoProvider(
            unifiedsearch => (
                after => 'middle',
                func  => \&searchInfoMenu,
            )
        );
        1;
    };

    if (!$registered) {
        $log->error('UnifiedSearch could not register Global Search provider: ' . ($@ || 'unknown error'));
        return;
    }

    $log->warn('UnifiedSearch registered Global Search provider');
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
        url       => 'http://192.168.178.99:9001/search.html?ajaxSearch=1&q=' . $escaped,
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
    Slim::Menu::GlobalSearch->deregisterInfoProvider('unifiedsearch');
}

1;
