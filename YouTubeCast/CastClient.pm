package CastClient;

use strict;
use warnings;

use IO::Select;
use IO::Socket::SSL;
use JSON::XS qw(encode_json decode_json);
use Time::HiRes qw(time sleep);
use HTTP::Tiny;
use URI::Escape qw(uri_escape_utf8);

use constant CAST_PORT        => 8009;
use constant YOUTUBE_APP_ID   => '233637DE';
use constant RECEIVER_NS      => 'urn:x-cast:com.google.cast.receiver';
use constant CONNECTION_NS    => 'urn:x-cast:com.google.cast.tp.connection';
use constant HEARTBEAT_NS     => 'urn:x-cast:com.google.cast.tp.heartbeat';
use constant LOUNGE_NS        => 'urn:x-cast:com.google.youtube.mdx';
use constant RECEIVER_ID      => 'receiver-0';
use constant SENDER_ID        => 'sender-0';
use constant LOUNGE_TOKEN_URL => 'https://www.youtube.com/api/lounge/pairing/get_lounge_token_batch';
use constant LOUNGE_BIND_URL => 'https://www.youtube.com/api/lounge/bc/bind';
use constant YOUTUBE_BASE_URL => 'https://www.youtube.com/';

sub cast_youtube {
    my ($class, $host, $videoId) = @_;
    die 'Invalid Chromecast host' unless $host && $host =~ /\A[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?\z/;
    die 'Invalid YouTube video ID' unless $videoId && $videoId =~ /\A[A-Za-z0-9_-]{11}\z/;

    my $socket = IO::Socket::SSL->new(
        PeerHost        => $host,
        PeerPort        => CAST_PORT,
        Timeout         => 5,
        SSL_verify_mode => 0,
    ) or die "Could not connect to Chromecast $host: $IO::Socket::SSL::SSL_ERROR";
    $socket->autoflush(1);

    _sendMessage($socket, RECEIVER_ID, CONNECTION_NS, { type => 'CONNECT' });
    _sendMessage($socket, RECEIVER_ID, RECEIVER_NS, {
        type      => 'LAUNCH',
        appId     => YOUTUBE_APP_ID,
        requestId => 1,
    });

    sleep(0.5);
    my $requestId = 2;
    _sendMessage($socket, RECEIVER_ID, RECEIVER_NS, {
        type      => 'GET_STATUS',
        requestId => $requestId++,
    });

    my $deadline = time() + 20;
    my $transportId;
    while (time() < $deadline) {
        my $message = _readMessage($socket, $deadline - time());
        if ($message->{namespace} eq HEARTBEAT_NS) {
            my $heartbeat = eval { decode_json($message->{payload}) };
            _sendMessage($socket, $message->{source} || RECEIVER_ID, HEARTBEAT_NS, { type => 'PONG' })
                if ref($heartbeat) eq 'HASH' && ($heartbeat->{type} || '') eq 'PING';
            next;
        }
        next unless $message->{namespace} eq RECEIVER_NS;

        my $payload = eval { decode_json($message->{payload}) };
        next unless ref($payload) eq 'HASH' && ($payload->{type} || '') eq 'RECEIVER_STATUS';

        my $applications = $payload->{status}{applications} || [];
        for my $application (@$applications) {
            next unless ($application->{appId} || '') eq YOUTUBE_APP_ID;
            $transportId = $application->{transportId};
            last;
        }
        last if $transportId;

        sleep(0.5);
        _sendMessage($socket, RECEIVER_ID, RECEIVER_NS, {
            type      => 'GET_STATUS',
            requestId => $requestId++,
        });
    }
    die 'Chromecast did not start the YouTube app' unless $transportId;

    _sendMessage($socket, $transportId, CONNECTION_NS, { type => 'CONNECT' });
    _sendMessage($socket, $transportId, LOUNGE_NS, { type => 'getMdxSessionStatus' });
    my $screenId = _youtubeScreenId($socket, $transportId);
    _playVideo($screenId, $videoId);
    close $socket;
    return 1;
}

sub _youtubeScreenId {
    my ($socket, $transportId) = @_;
    my $deadline = time() + 10;

    while (time() < $deadline) {
        my $message = _readMessage($socket, $deadline - time());
        if ($message->{namespace} eq HEARTBEAT_NS) {
            my $heartbeat = eval { decode_json($message->{payload}) };
            _sendMessage($socket, $message->{source} || $transportId, HEARTBEAT_NS, { type => 'PONG' })
                if ref($heartbeat) eq 'HASH' && ($heartbeat->{type} || '') eq 'PING';
            next;
        }
        next unless $message->{namespace} eq LOUNGE_NS;

        my $payload = eval { decode_json($message->{payload}) };
        next unless ref($payload) eq 'HASH' && ($payload->{type} || '') eq 'mdxSessionStatus';
        my $screenId = ref($payload->{data}) eq 'HASH' ? $payload->{data}{screenId} : undef;
        return $screenId if defined $screenId && length $screenId;
    }

    die 'YouTube app did not provide an MDX screen ID';
}

sub _playVideo {
    my ($screenId, $videoId) = @_;
    my $http = HTTP::Tiny->new(timeout => 10, agent => 'LyrionYouTubeCast/0.1.7');
    my $tokenResponse = $http->post_form(LOUNGE_TOKEN_URL, { screen_ids => $screenId });
    die _httpError('Could not get YouTube Lounge token', $tokenResponse)
        unless $tokenResponse->{success};

    my $tokenData = eval { decode_json($tokenResponse->{content}) };
    my $screen = ref($tokenData) eq 'HASH' && ref($tokenData->{screens}) eq 'ARRAY'
        ? $tokenData->{screens}[0]
        : undef;
    my $loungeToken = ref($screen) eq 'HASH' ? $screen->{loungeToken} : undef;
    die 'YouTube did not return a Lounge token for the Chromecast'
        unless defined $loungeToken && length $loungeToken;

    my %headers = (
        Origin       => YOUTUBE_BASE_URL,
        'X-YouTube-LoungeId-Token' => $loungeToken,
    );
    my $bindResponse = $http->post_form(
        _loungeUrl({ RID => 0, VER => 8, CVER => 1 }),
        {
            device        => 'REMOTE_CONTROL',
            id            => 'aaaaaaaaaaaaaaaaaaaaaaaaaa',
            name          => 'Lyrion LMS',
            'mdx-version' => 3,
            pairing_type  => 'cast',
            app           => 'android-phone-13.14.55',
        },
        { headers => \%headers },
    );
    die _httpError('Could not establish YouTube Lounge session', $bindResponse)
        unless $bindResponse->{success};

    my $bindBody = $bindResponse->{content} || '';
    my ($sid) = $bindBody =~ /"c","([^"]+)",/;
    my ($gsessionId) = $bindBody =~ /"S","([^"]+)"\]/;
    die 'YouTube Lounge response did not contain session identifiers'
        unless defined $sid && defined $gsessionId;

    my %playData = (
        req0_listId      => '',
        req0__sc         => 'setPlaylist',
        req0_currentTime  => 0,
        req0_currentIndex => -1,
        req0_audioOnly    => 'false',
        req0_videoId      => $videoId,
        count             => 1,
    );
    my $playResponse = $http->post_form(
        _loungeUrl({
            SID        => $sid,
            gsessionid => $gsessionId,
            RID        => 1,
            VER        => 8,
            CVER       => 1,
        }),
        \%playData,
        { headers => \%headers },
    );
    die _httpError('YouTube rejected the video play request', $playResponse)
        unless $playResponse->{success};
}

sub _loungeUrl {
    my ($params) = @_;
    return LOUNGE_BIND_URL . '?' . join '&',
        map { uri_escape_utf8($_) . '=' . uri_escape_utf8($params->{$_}) }
        sort keys %$params;
}

sub _httpError {
    my ($message, $response) = @_;
    my $detail = $response->{reason} || 'unknown HTTP error';
    return "$message: HTTP $response->{status} $detail";
}

sub _sendMessage {
    my ($socket, $destination, $namespace, $payload) = @_;
    my $json = encode_json($payload);
    my $message = _fieldVarint(1, 0)
        . _fieldBytes(2, SENDER_ID)
        . _fieldBytes(3, $destination)
        . _fieldBytes(4, $namespace)
        . _fieldVarint(5, 0)
        . _fieldBytes(6, $json);
    my $frame = pack('N', length($message)) . $message;

    my $written = 0;
    while ($written < length($frame)) {
        my $count = $socket->syswrite($frame, length($frame) - $written, $written);
        die "Chromecast write failed: $!" unless defined $count && $count > 0;
        $written += $count;
    }
}

sub _readMessage {
    my ($socket, $timeout) = @_;
    my $header = _readExact($socket, 4, $timeout);
    my $size = unpack('N', $header);
    die 'Invalid Chromecast message size' unless $size && $size <= 1_048_576;
    return _decodeMessage(_readExact($socket, $size, $timeout));
}

sub _readExact {
    my ($socket, $size, $timeout) = @_;
    my $selector = IO::Select->new($socket);
    my $deadline = time() + $timeout;
    my $buffer = '';

    while (length($buffer) < $size) {
        my $remaining = $deadline - time();
        die 'Timed out waiting for Chromecast response' if $remaining <= 0;
        unless ($socket->pending || $selector->can_read($remaining)) {
            die 'Timed out waiting for Chromecast response';
        }

        my $count = $socket->sysread(my $chunk, $size - length($buffer));
        die "Chromecast read failed: $!" unless defined $count && $count > 0;
        $buffer .= $chunk;
    }

    return $buffer;
}

sub _decodeMessage {
    my ($data) = @_;
    my %message;
    my $offset = 0;

    while ($offset < length($data)) {
        my $key = _readVarint($data, \$offset);
        my $field = $key >> 3;
        my $wireType = $key & 7;

        if ($wireType == 2) {
            my $size = _readVarint($data, \$offset);
            die 'Invalid Chromecast field length' if $size > length($data) - $offset;
            my $value = substr($data, $offset, $size);
            $offset += $size;
            $message{3} = $value if $field == 3;
            $message{4} = $value if $field == 4;
            $message{6} = $value if $field == 6;
        }
        elsif ($wireType == 0) {
            _readVarint($data, \$offset);
        }
        elsif ($wireType == 1) {
            $offset += 8;
        }
        elsif ($wireType == 5) {
            $offset += 4;
        }
        else {
            die 'Unsupported Chromecast protobuf wire type';
        }

        die 'Invalid Chromecast message field' if $offset > length($data);
    }

    return {
        source    => $message{3} || '',
        namespace => $message{4} || '',
        payload   => $message{6} || '',
    };
}

sub _fieldVarint {
    my ($field, $value) = @_;
    return _varint(($field << 3) | 0) . _varint($value);
}

sub _fieldBytes {
    my ($field, $value) = @_;
    return _varint(($field << 3) | 2) . _varint(length($value)) . $value;
}

sub _varint {
    my ($value) = @_;
    my $encoded = '';
    while ($value > 127) {
        $encoded .= chr(($value & 127) | 128);
        $value >>= 7;
    }
    return $encoded . chr($value);
}

sub _readVarint {
    my ($data, $offsetRef) = @_;
    my $value = 0;
    my $shift = 0;

    while ($$offsetRef < length($data) && $shift <= 63) {
        my $byte = ord(substr($data, $$offsetRef, 1));
        $$offsetRef++;
        $value |= ($byte & 127) << $shift;
        return $value unless $byte & 128;
        $shift += 7;
    }

    die 'Invalid Chromecast protobuf varint';
}

1;
