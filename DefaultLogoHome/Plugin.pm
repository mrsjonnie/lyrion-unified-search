package Plugins::DefaultLogoHome::Plugin;

use strict;
use warnings;
use base qw(Slim::Plugin::Base);
use Slim::Utils::Log;

my $enabled = 0;
my $registered = 0;
my $log = Slim::Utils::Log->addLogCategory({
    category     => 'plugin.defaultlogohome',
    defaultLevel => 'WARN',
    description  => 'Default skin logo links to the LMS home page',
});

sub initPlugin {
    my $class = shift;
    $enabled = main::WEBUI ? 1 : 0;
    return unless $enabled;

    return if $registered;

    require Slim::Web::Pages;

    my $homeHandler = Slim::Web::Pages->getPageFunction('index.html');
    if (!$homeHandler) {
        $log->error('DefaultLogoHome could not find the LMS home page handler');
        return;
    }

    my $homePage = sub {
        my $params = $_[1];
        my $page = $homeHandler->(@_);
        return $page unless $enabled
            && ($params->{systemSkin} // '') eq 'Default'
            && ref($page) eq 'SCALAR';

        my $html = $$page;
        my $webroot = $params->{webroot} || '/';
        $webroot =~ s{Default/?$}{}i;
        $webroot = '/' unless length $webroot;
        $html =~ s{(<a\b[^>]*\bhref=["'])https?://(?:www\.)?lyrion\.org/?(["'])}{$1$webroot$2}i;
        return \$html;
    };

    Slim::Web::Pages->addPageFunction(qr/^$/, $homePage);
    Slim::Web::Pages->addPageFunction(qr/^index\.(?:htm|xml)/, $homePage);
    $registered = 1;
}

sub shutdownPlugin {
    $enabled = 0;
}

sub getDisplayName {
    return 'PLUGIN_DEFAULTLOGOHOME';
}

1;
