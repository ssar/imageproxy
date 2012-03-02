use strict;
use HTTP::Proxy;
use HTTP::Proxy::BodyFilter::complete;
use HTTP::Proxy::BodyFilter::simple;
use IPC::Open2;
use Redis;

my $proxy = HTTP::Proxy->new( port => 3128 );

my $command = 'convert -  -modulate 100,0 \( +clone -selective-blur 4x2+50% -negate \) -compose dissolve -define compose:args=\'50,100\' -composite \( +clone \) -compose color_dodge -composite  \( +clone \) -compose multiply -composite \( +clone \) -compose multiply -composite - ';
#my $command = 'convert -  -flip - ';
#my $command = 'convert -  -charcoal 5 - ';

my $redis = Redis->new(encoding => undef, reconnect => 60);

$proxy->push_filter(
		mime	=> 'image/*',
		response => HTTP::Proxy::BodyFilter::complete->new,
        response => HTTP::Proxy::BodyFilter::simple->new(
            sub {
                my ( $self, $dataref, $message, $protocol, $buffer ) = @_;
				defined $buffer and return;
				my $key = "sketch-proxy:0.0.7:" . $message->base;
				my $ret = $redis->get($key);
				if($ret) {
					$$dataref = $ret;
					return;
				}
				my($chld_out, $chld_in);
				my $pid = open2($chld_out, $chld_in, $command);
				binmode $chld_out;
				binmode $chld_in;
				print $chld_in $$dataref;
				close $chld_in;
				my ($buf, $data, $n);
				while (($n = read $chld_out, $data, 65536) != 0) {
					$buf .= $data;
				}
				$$dataref = $buf;
				$redis->set($key,$buf);
				$redis->expire($key,24*60*60);
            }
        )
	);

$proxy->engine->max_clients(500);

$proxy->start;
