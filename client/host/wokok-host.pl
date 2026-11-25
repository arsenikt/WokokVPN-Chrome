#!/usr/bin/env perl
# Wokok VPN native messaging host (macOS / Linux). Core Perl only: no installs needed.
use strict; use warnings;
use JSON::PP; use IO::Socket::INET; use POSIX qw(setsid); use Time::HiRes qw(time sleep);
use MIME::Base64 qw(decode_base64);

my $VERSION = "2.1.9";
my $BASE_PORT = 10808;   # preferred local SOCKS port; next free one is used if busy
my $SOCKS = $BASE_PORT;
my $D = ($^O eq 'darwin') ? "$ENV{HOME}/Library/Application Support/WokokVPN" : ($ENV{XDG_DATA_HOME} || "$ENV{HOME}/.local/share") . "/wokokvpn";
my $RUN = "$D/run"; my $XRAY = "$D/bin/xray"; my $STATE = "$RUN/state.json";
my $J = JSON::PP->new->utf8->canonical;
system('mkdir', '-p', $RUN);

sub read_msg { binmode STDIN; my $n = read(STDIN, my $l, 4); return {} unless $n && $n == 4;
  my $len = unpack('V', $l); read(STDIN, my $b, $len); return eval { $J->decode($b) } || {}; }
sub send_msg { my $b = $J->encode($_[0]); binmode STDOUT; print STDOUT pack('V', length $b), $b; }
sub slurp { open my $f, '<', $_[0] or return undef; local $/; my $c = <$f>; close $f; $c }
sub spew  { open my $f, '>', $_[0] or die "write $_[0]: $!"; print $f $_[1]; close $f }
sub state { my $c = slurp($STATE); $c ? eval { $J->decode($c) } : undef }
sub alive { my $p = shift; $p && kill(0, $p) }
sub now_ms { int(time * 1000) }
{ my $s0 = state(); $SOCKS = $s0->{port} if $s0 && $s0->{port}; }
sub port_free { my $l = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => $_[0], Listen => 1, ReuseAddr => 0) or return 0; close $l; 1 }
sub find_free { for my $p ($BASE_PORT .. $BASE_PORT + 49) { return $p if port_free($p) } die "no free local port in $BASE_PORT-" . ($BASE_PORT + 49) . "
" }
sub stop_orphans { system('pkill', '-f', "$RUN/") }

sub port_ms { my ($h, $p, $t) = @_; my $t0 = time;
  my $s = IO::Socket::INET->new(PeerAddr => $h, PeerPort => $p, Timeout => ($t || 0.8)) or return -1;
  close $s; int((time - $t0) * 1000) }

sub curl { my @a = @_; open my $f, '-|', 'curl', '-s', '--socks5-hostname', "127.0.0.1:$SOCKS", @a or return '';
  local $/; my $o = <$f> // ''; close $f; $o }

sub tunnel_ms { my $r = curl('-o', '/dev/null', '-m', $_[0] || 6, '-w', '%{http_code} %{time_total}', 'http://www.gstatic.com/generate_204');
  my ($code, $t) = split / /, $r; ($code && $code eq '204') ? int($t * 1000) : -1 }

sub spawn_detached { my @cmd = @_; my $pid = fork(); die "fork: $!" unless defined $pid;
  if ($pid == 0) { setsid(); my $p2 = fork(); if ($p2) { spew("$RUN/child.pid", $p2); POSIX::_exit(0) }
    open STDIN, '<', '/dev/null'; open STDOUT, '>', '/dev/null'; open STDERR, '>', '/dev/null'; { no warnings; exec { $cmd[0] } @cmd } POSIX::_exit(1) }
  waitpid($pid, 0); my $c = slurp("$RUN/child.pid"); unlink "$RUN/child.pid"; int($c || 0) }

sub stop_tunnel { my $s = state(); kill('TERM', $s->{pid}) if $s && alive($s->{pid}); unlink $STATE }

sub wait_up { my $pid = shift;
  for (1..20) { sleep 0.3; return -1 unless alive($pid); return tunnel_ms(6) if port_ms('127.0.0.1', $SOCKS, 0.3) >= 0 } -1 }

sub start_reality { my $s = shift; die "xray not found - rerun the installer\n" unless -x $XRAY;
  die "server port $s->{port} is unreachable: open TCP $s->{port} in your VPS firewall/provider panel, or check that Xray runs (sudo wokok status)
" if port_ms($s->{host}, $s->{port}, 3.5) < 0;
  my $cfg = { log => { loglevel => 'warning', error => "$RUN/xray.log" },
    inbounds => [{ listen => '127.0.0.1', port => $SOCKS, protocol => 'socks', settings => { udp => JSON::PP::true },
      sniffing => { enabled => JSON::PP::true, destOverride => ['http','tls','quic'], routeOnly => JSON::PP::true } }],
    outbounds => [{ protocol => 'vless',
      settings => { vnext => [{ address => $s->{host}, port => $s->{port} + 0, users => [{ id => $s->{id}, encryption => 'none', flow => 'xtls-rprx-vision' }] }] },
      streamSettings => { network => 'tcp', security => 'reality',
        realitySettings => { serverName => $s->{sni}, fingerprint => 'chrome', publicKey => $s->{pbk}, shortId => "$s->{sid}", spiderX => '' } } }] };
  spew("$RUN/xray.json", $J->encode($cfg));
  my $pid = spawn_detached($XRAY, 'run', '-c', "$RUN/xray.json"); ($pid, wait_up($pid)) }

sub start_ssh { my $s = shift; die "no SSH fallback in this link\n" unless $s->{ssh};
  die "SSH port $s->{ssh}{port} is unreachable (check the real SSH port of your server)
" if port_ms($s->{host}, $s->{ssh}{port}, 3.5) < 0;
  my $key = "$RUN/ssh_key"; spew($key, decode_base64($s->{ssh}{key})); chmod 0600, $key;
  my $pid = spawn_detached('ssh', '-i', $key, '-N', '-T', '-D', "127.0.0.1:$SOCKS", '-p', $s->{ssh}{port},
    '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes', '-o', 'ExitOnForwardFailure=yes',
    '-o', 'ServerAliveInterval=20', '-o', 'ServerAliveCountMax=3', '-o', 'StrictHostKeyChecking=accept-new',
    '-o', "UserKnownHostsFile=$D/known_hosts", '-E', "$RUN/ssh.log", "$s->{ssh}{user}\@$s->{host}");
  ($pid, wait_up($pid)) }

sub connect_ { my ($s, $prefer) = @_; stop_tunnel(); stop_orphans(); sleep 0.2;
  $SOCKS = eval { find_free() }; return { ok => JSON::PP::false, error => "$@" } unless $SOCKS;
  my @order = ($prefer // '') eq 'ssh' ? ('ssh') : ($prefer // '') eq 'reality' ? ('reality') : ('reality', 'ssh');
  my @err;
  for my $mode (@order) {
    my ($pid, $ms) = eval { $mode eq 'reality' ? start_reality($s) : start_ssh($s) };
    if ($@) { chomp(my $e = $@); push @err, "$mode: $e"; next }
    if ($ms >= 0) { spew($STATE, $J->encode({ pid => $pid, mode => $mode, since => now_ms(), server => $s->{host}, port => $SOCKS }));
      return { ok => JSON::PP::true, connected => JSON::PP::true, mode => $mode, socksPort => $SOCKS, ping => $ms } }
    kill('TERM', $pid) if alive($pid); push @err, "$mode: connected, but no internet through the tunnel (wrong keys, SNI or server time?)";
  }
  return { ok => JSON::PP::false, connected => JSON::PP::false, error => join('; ', @err) } }

sub status_ { my $s = state(); my $up = $s && alive($s->{pid}) && port_ms('127.0.0.1', $SOCKS, 0.4) >= 0;
  return { ok => JSON::PP::true, connected => $up ? JSON::PP::true : JSON::PP::false, mode => $up ? $s->{mode} : undef,
    socksPort => $SOCKS, version => $VERSION, platform => $^O } }

sub info_ { my $ms = tunnel_ms(6); return { ok => JSON::PP::false, error => 'tunnel is not answering' } if $ms < 0;
  my $j = eval { $J->decode(curl('-m', 8, 'https://ipwho.is/')) } || {};
  return { ok => JSON::PP::true, ping => $ms, ip => $j->{ip}, country => $j->{country}, cc => $j->{country_code}, city => $j->{city},
    isp => ($j->{connection} || {})->{isp} } }

sub speed_ { my $r = curl('-o', '/dev/null', '-m', 20, '-w', '%{speed_download}', 'https://speed.cloudflare.com/__down?bytes=25000000');
  my $mbps = sprintf('%.1f', ($r || 0) * 8 / 1e6) + 0; return { ok => $mbps > 0 ? JSON::PP::true : JSON::PP::false, mbps => $mbps } }

sub ping_ { return { ok => JSON::PP::true, results => [ map { +{ id => $_->{id}, ms => port_ms($_->{host}, $_->{port}, 2) } } @{ $_[0] || [] } ] } }

my $m = read_msg(); my $c = $m->{cmd} // 'status';
my $reply = eval {
  $c eq 'connect'    ? connect_($m->{server}, $m->{prefer}) :
  $c eq 'disconnect' ? do { stop_tunnel(); +{ ok => JSON::PP::true, connected => JSON::PP::false } } :
  $c eq 'info'       ? info_() :
  $c eq 'speed'      ? speed_() :
  $c eq 'ping'       ? ping_($m->{targets}) : status_() };
send_msg($reply || { ok => JSON::PP::false, error => "$@" });
