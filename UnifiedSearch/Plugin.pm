package Plugins::UnifiedSearch::Plugin;

use strict;
use warnings;
use base qw(Slim::Plugin::OPMLBased);

use URI::Escape qw(uri_escape_utf8);
use Slim::Menu::GlobalSearch;
use Slim::Utils::Log;
use Slim::Utils::Network;
use Slim::Utils::PluginManager;
use Slim::Utils::Strings qw(string);

our $VERSION = '0.3.1';

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
    my $escaped = uri_escape_utf8($query);

    push @items, {
        name      => string('PLUGIN_UNIFIEDSEARCH_LOCAL'),
        type      => 'link',
        url       => Slim::Utils::Network::serverURL() . '/search.html?ajaxSearch=1&q=' . $escaped,
        cachetime => 0,
    };

    # SpotOn is optional. Keep the local-library result even if SpotOn
    # cannot be loaded or its search callback is unavailable.
    if (Slim::Utils::PluginManager->isEnabled('Plugins::SpotOn::Plugin')) {
        my $loaded = eval { require Plugins::SpotOn::Plugin; 1 };
        if (!$loaded) {
            $log->warn('SpotOn search unavailable: could not load plugin: ' . ($@ || 'unknown error'));
        }
        elsif (Plugins::SpotOn::Plugin->can('_searchFromHistoryFeed')) {
            push @items, {
                name        => string('PLUGIN_UNIFIEDSEARCH_SPOTON'),
                type        => 'link',
                url         => \&Plugins::SpotOn::Plugin::_searchFromHistoryFeed,
                passthrough => [{ query => $query }],
                cachetime   => 0,
            };
        }
        else {
            $log->warn('SpotOn search unavailable: _searchFromHistoryFeed callback not found');
        }
    }

    $log->debug('UnifiedSearch returning ' . scalar(@items) . ' search item(s)');
    return @items ? \@items : undef;
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
