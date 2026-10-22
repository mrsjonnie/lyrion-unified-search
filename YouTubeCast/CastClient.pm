package CastClient;

use strict;
use warnings;

use IO::Select;
use IO::Socket::SSL;
use JSON::XS qw(encode_json decode_json);
use Time::HiRes qw(time sleep);

use constant CAST_PORT       => 8009;
use constant YOUTUBE_APP_ID  => '233637DE';
use constant YOUTUBE_NS     => 'urn:x-cast:com.google.youtube.mdx';
use constant RECEIVER_NS    => 'urn:x-cast:com.google.cast.receiver';
use constant CONNECTION_NS  => 'urn:x-cast:com.google.cast.tp.connection';
use constant HEARTBEAT_NS   => 'urn:x-cast:com.google.cast.tp.heartbeat';
use constant RECEIVER_ID    => 'receiver-0';
use constant SENDER_ID      => 'sender-0';

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
    sleep(0.25);
    _sendMessage($socket, $transportId, YOUTUBE_NS, {
        type => 'flingVideo',
        data => {
            currentTime => 0,
            videoId     => $videoId,
            doSeek      => JSON::XS::true,
        },
    });

    close $socket;
    return 1;
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
