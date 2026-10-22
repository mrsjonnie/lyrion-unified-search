package Plugins::DefaultLogoHome::Plugin;

use strict;
use warnings;
use base qw(Slim::Plugin::Base);

sub initPlugin {
    my $class = shift;
    return unless main::WEBUI;

    require Slim::Web::Pages;
    require Slim::Web::Pages::JS;

    Slim::Web::Pages->addPageFunction("js-main-logo-home.js", sub {
        my ($client, $params) = @_;
        return Slim::Web::HTTP::filltemplatefile("js-main-logo-home.js", $params);
    });

    Slim::Web::Pages::JS->addJSFunction("js-main", "js-main-logo-home.js");
}

sub getDisplayName {
    return 'PLUGIN_DEFAULTLOGOHOME';
}

1;
