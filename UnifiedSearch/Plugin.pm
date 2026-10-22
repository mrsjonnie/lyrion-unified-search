package Plugins::UnifiedSearch::Plugin;

use strict;
use warnings;
use base qw(Slim::Plugin::Base);

use URI::Escape qw(uri_escape_utf8);
use File::Path qw(make_path);
use Slim::Menu::GlobalSearch;
use Slim::Utils::Log;

our $VERSION = '0.1.8';

my $log = Slim::Utils::Log->addLogCategory({
    category     => 'plugin.unifiedsearch',
    defaultLevel => 'WARN',
    description  => 'Lyrion Unified Search',
});

my $MATERIAL_HOOK_START = '/* BEGIN LYRION UNIFIED SEARCH */';
my $MATERIAL_HOOK_END   = '/* END LYRION UNIFIED SEARCH */';

sub initPlugin {
    my $class = shift;

    $log->warn("UnifiedSearch v$VERSION initPlugin called");

    # Material Skin filters Global Search results by a fixed list of source
    # titles in search-field.js. Add our two source names through its supported
    # custom.js mechanism, preserving any user-owned JavaScript in that file.
    _installMaterialSkinSearchHook();

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

sub _materialSkinHook {
    return <<'JS';
/* BEGIN LYRION UNIFIED SEARCH */
(function () {
    function registerUnifiedSearchSources() {
        try {
            if (typeof SEARCH_OTHER === "undefined") {
                return;
            }
            SEARCH_OTHER["local library"] = { icon: "library-music" };
            SEARCH_OTHER["spotify (spoton)"] = { svg: "spotify" };
        } catch (err) {
            if (window.console && console.warn) {
                console.warn("Lyrion Unified Search: could not register Material Skin sources", err);
            }
        }
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", registerUnifiedSearchSources, { once: true });
    } else {
        registerUnifiedSearchSources();
    }
})();
/* END LYRION UNIFIED SEARCH */
JS
}

sub _installMaterialSkinSearchHook {
    my $enabled = eval { Slim::Utils::PluginManager->isEnabled('Plugins::MaterialSkin::Plugin') };
    if (!$enabled) {
        $log->warn('Material Skin is not enabled; skipping its search-filter hook');
        return;
    }

    my $prefs_dir = eval { Slim::Utils::Prefs::dir() };
    if (!$prefs_dir) {
        $log->warn('Could not determine LMS preferences directory; skipping Material Skin hook');
        return;
    }

    my $dir = "$prefs_dir/material-skin";
    if (!-d $dir) {
        eval { make_path($dir); 1 } or do {
            $log->warn("Could not create Material Skin preferences directory $dir: " . ($@ || 'unknown error'));
            return;
        };
    }

    my $path = "$dir/custom.js";
    my $existing = '';
    if (-e $path) {
        if (!open(my $in, '<', $path)) {
            $log->warn("Could not read $path: $!");
            return;
        }
        local $/;
        $existing = <$in> // '';
        close $in;
    }

    # Idempotent: do not append another copy after a server restart.
    if (index($existing, $MATERIAL_HOOK_START) >= 0) {
        return;
    }

    my $updated = $existing;
    $updated .= "\n" if length($updated) && $updated !~ /\n\z/;
    $updated .= _materialSkinHook() . "\n";

    my $tmp = "$path.unifiedsearch.tmp";
    if (!open(my $out, '>', $tmp)) {
        $log->warn("Could not write temporary Material Skin hook $tmp: $!");
        return;
    }
    print {$out} $updated;
    if (!close $out) {
        unlink $tmp;
        $log->warn("Could not finish writing Material Skin hook $tmp: $!");
        return;
    }
    if (!rename($tmp, $path)) {
        unlink $tmp;
        $log->warn("Could not install Material Skin hook at $path: $!");
        return;
    }

    $log->warn('Installed Material Skin Global Search source filter hook');
}

sub _removeMaterialSkinSearchHook {
    my $prefs_dir = eval { Slim::Utils::Prefs::dir() };
    return unless $prefs_dir;

    my $path = "$prefs_dir/material-skin/custom.js";
    return unless -e $path;

    if (!open(my $in, '<', $path)) {
        $log->warn("Could not read $path to remove Material Skin hook: $!");
        return;
    }
    local $/;
    my $existing = <$in> // '';
    close $in;

    my $start = quotemeta($MATERIAL_HOOK_START);
    my $end   = quotemeta($MATERIAL_HOOK_END);
    my $count = ($existing =~ s/\n?\Q$MATERIAL_HOOK_START\E.*?\Q$MATERIAL_HOOK_END\E\n?//s);
    return unless $count;

    my $tmp = "$path.unifiedsearch.tmp";
    if (!open(my $out, '>', $tmp)) {
        $log->warn("Could not write temporary Material Skin hook cleanup $tmp: $!");
        return;
    }
    print {$out} $existing;
    if (!close $out) {
        unlink $tmp;
        $log->warn("Could not finish cleaning Material Skin hook $tmp: $!");
        return;
    }
    if (!rename($tmp, $path)) {
        unlink $tmp;
        $log->warn("Could not remove Material Skin hook from $path: $!");
        return;
    }

    $log->warn('Removed Material Skin Global Search source filter hook');
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
    # Remove only our marked block. Material Skin's own custom.js content is
    # preserved, and initPlugin reinstalls this block on a normal LMS restart.
    _removeMaterialSkinSearchHook();
}

1;
