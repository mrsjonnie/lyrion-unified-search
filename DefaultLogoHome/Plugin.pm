package Plugins::DefaultLogoHome::Plugin;

use strict;
use warnings;
use base qw(Slim::Plugin::Base);

my $enabled = 0;
my $registered = 0;

sub initPlugin {
    my $class = shift;
    $enabled = main::WEBUI ? 1 : 0;
    return unless $enabled;

    return if $registered;

    require Slim::Web::Pages;
    require Slim::Web::Pages::JS;

    Slim::Web::Pages->addPageFunction("js-main-logo-home.js", sub {
        return \'' unless $enabled;

        my ($client, $params) = @_;
        return Slim::Web::HTTP::filltemplatefile("js-main-logo-home.js", $params);
    });

    Slim::Web::Pages::JS->addJSFunction("js-main", "js-main-logo-home.js");
    $registered = 1;
}

sub shutdownPlugin {
    $enabled = 0;
}

sub getDisplayName {
    return 'PLUGIN_DEFAULTLOGOHOME';
}

1;
