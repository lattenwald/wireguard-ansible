#!/usr/bin/env perl
use strict;
use warnings;
use feature 'say';

use Cwd qw/cwd/;
use IPC::Open2;
use File::Copy;

#############
### constants

my $wg_exe = '/usr/bin/wg';
my $qrencode_exe = '/usr/bin/qrencode';

my $workdir = '/etc/wireguard';
my $tmpl_server = $workdir . '/server.tmpl';
my $tmpl_client = $workdir . '/client.tmpl';
my $config = $workdir . '/wg0.conf';
my $clients_dir = $workdir . '/clients';

################
### basic checks

if ($>) {
    die "Please run as root\n";
}

chdir $workdir or die $!;

for ($wg_exe, $qrencode_exe) {
    -x $_ or die "Need executable '$_'";
}

-w $config or die "Need writeable '$config'";
-d $clients_dir or die "Need '$clients_dir/' directory";

for ($tmpl_server, $tmpl_client) {
    -r $_ or die "Need readable '$_'";
}

#########################
### function declarations

sub usage();
sub list_clients();
sub add_client($);
sub remove_client($);

###################
### options parsing

my $action = shift || '';

if ($action eq 'list') {
    list_clients();
} elsif ($action eq 'add') {
    my $client = shift or die "need client name";
    add_client($client);
} elsif ($action eq 'remove') {
    my $client = shift or die "need client name";
    remove_client($client);
} else {
    usage();
}
exit;

#############
### functions

sub usage() {
    print <<USAGE
  Usage:
    Add new client: $0 add <client>
    Remove client:  $0 remove <client>
    List clients:   $0 list
    Help:           $0 help
USAGE
}

sub list_clients() {
    open my $F, '<', $config or die $!;

    my $wg_data = `wg show`;
    my %connections;
    while ($wg_data =~ /allowed ips:\s+([^\/]+).+?latest handshake:\s+([^\n]*)/gsm) {
        $connections{$1} = $2;
    }

    open my $Conf, '<', $config or die $!;
    undef $/;
    my $conf = <$Conf>;
    close $Conf or die $!;

    while($conf =~ /^#\s*friendly_name\s*=\s*([^\n]+).+?AllowedIPs\s*=\s*([^\/ ]+)/gsm) {
        printf "%-10s  %-10s  %s\n", $1, $2, ($connections{$2} ? "\t$connections{$2}" : "");
    }
}

sub add_client($) {
    undef $/;


    ## checks
    my ($client) = @_;
    $client =~ /^[\w\d]+$/ or die "invalid client name";

    my $client_conf_file = "$clients_dir/$client.conf";
    -e $client_conf_file and die "'$client_conf_file' already exists";

    open my $Conf, '<', $config or die $!;
    my $conf = <$Conf>;
    close $Conf or die $!;
    $conf =~ /^#\s*friendly_name\s*=\s*\Q$client\E\s*$/m and die "'$client' already present in $config";


    say "Adding client '$client'";

    ## keys generation
    my $key_file = "$clients_dir/$client.key";
    my $pub_key_file = "$key_file.pub";

    my $key = `wg genkey`;
    $key =~ s/\s+$//;

    my $pid = open2(my $PKeyOut, my $PKeyIn, 'wg', 'pubkey');
    print $PKeyIn $key;
    close $PKeyIn or die $!;
    my ($pkey) = <$PKeyOut>;
    waitpid($pid, 0);
    $pkey =~ s/\s+$//;


    ## derive client address
    my @addresses = $conf =~ /^(?:Address|AllowedIPs)\s*=\s*(.*?)\//mg;
    my $last_client_address = $addresses[$#addresses];
    (my $next_client_address = $last_client_address) =~ s/(?<=\.)(\d+)$/$1+1/e;


    ## client config
    open my $TmplC, '<', $tmpl_client or die $!;
    my $client_conf = <$TmplC>;
    close $TmplC or die $!;

    $client_conf =~ s/\Q{PrivateKey}\E/$key/;
    $client_conf =~ s/\Q{ClientAddress}\E/$next_client_address/;
    $client_conf =~ /[\{\}]/ and die "Invalid client template";


    ## server config
    open my $TmplS, '<', $tmpl_server or die $1;
    my $server_conf = <$TmplS>;
    close $TmplS or die $!;

    $server_conf =~ s/\Q{ClientName}\E/$client/;
    $server_conf =~ s/\Q{PublicKey}\E/$pkey/;
    $server_conf =~ s/\Q{ClientAddress}\E/$next_client_address/;
    $server_conf =~ /[\{\}]/ and die "Invalid server template";


    ## Writing stuff
    copy $config, $config . '.bak';

    open my $KeyFile, '>', $key_file or die $!;
    print $KeyFile $key;
    close $KeyFile or die $!;
    # say "writing to '$key_file', '>', $key";

    open my $PubKeyFile, '>', $pub_key_file or die $!;
    print $PubKeyFile $pkey;
    close $PubKeyFile or die $!;
    # say "writing to '$pub_key_file', '>', $pkey";

    open my $ClientConf, '>', $client_conf_file or die $1;
    print $ClientConf $client_conf;
    close $ClientConf or die $!;
    # say "writing to '$client_conf_file', '>', $client_conf";

    open my $ServerConf, '>>', $config or die $!;
    print $ServerConf $server_conf;
    close $ServerConf or die $!;

    system 'systemctl', 'restart', 'wg-quick@wg0';
    exec "qrencode -t ansiutf8 < '$client_conf_file'";
}

sub remove_client($) {
    my ($client) = @_;
    $client =~ /^[\w\d]+$/ or die "invalid client name";

    say "Removing client '$client'";

    undef $/;
    open my $Conf, '<', $config or die $!;
    my $conf = <$Conf>;
    my @conf = split /(?=^\[Peer\])/m, $conf;
    close $Conf or die $!;

    # whitespaces
    for (@conf) {
        s/^\s+//;
        s/\s+$//;
    }

    @conf = grep !/^#\s*friendly_name\s*=\s*\Q$client\E\s*$/m, @conf;

    open my $F, '>', $config or die $!;
    for (@conf) {
        print $F $_;
        print $F "\n\n";
    }
    close $F or die $!;

    unlink "$clients_dir/$client.conf", "$clients_dir/$client.key", "$clients_dir/$client.key.pub";

    system 'systemctl', 'restart', 'wg-quick@wg0';
}
