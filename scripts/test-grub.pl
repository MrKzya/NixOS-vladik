use strict;
use warnings;
use File::stat;
use File::Temp qw(tempdir);
use POSIX qw(tzset);
use Test::More;

require $ARGV[0];
my $temp = tempdir(CLEANUP => 1);
mkdir "$temp/store";
mkdir "$temp/other";
local $ENV{TZ} = "UTC";
tzset();
my $generator = do { local $/; open my $fh, '<', $ARGV[1] or die $!; <$fh> };
like($generator, qr/^addGeneration\("\@distroName\@", "", \$defaultConfig, \$entryOptions, 1\);$/m, "top-level NixOS entry");
my ($profileWriter) = $generator =~ /^(sub addProfile \{.*?^\})/ms;
our ($conf, $configurationLimit, $subEntryOptions, $generationTimeZone);
my @entries;
sub addGeneration { push @entries, $_[0] }
eval $profileWriter;
die $@ if $@;
is(system('touch', '-t', '197001010000.00', "$temp/store"), 0, 'normalize store target timestamp');
open my $version, '>', "$temp/store/nixos-version" or die $!;
close $version;
$configurationLimit = 0;
for my $i (1 .. 27) {
    my $link = "$temp/system-$i-link";
    symlink("$temp/store", $link) or die $!;
    system("touch", "-h", "-t", sprintf("2026112615%02d.00", $i), $link) == 0 or die "touch";
    is(generationLabel($link), sprintf("%d - 26_11_2026/15:%02d", $i, $i), "real time of generation $i");
    if (grep { $_ == $i } (1, 5, 10, 20, 27)) {
        $conf = '';
        @entries = ();
        addProfile("$temp/system", 'NixOS - All configurations');
        is_deeply(\@entries, [ map { sprintf("%d - 26_11_2026/15:%02d", $_, $_) } reverse 1 .. $i ], "$i generations newest first");
        is($conf, "submenu \"NixOS - All configurations\" --class submenu {\n}\n", 'submenu scope');
    }
}
symlink("$temp/store", "$temp/system-28-link") or die $!;
system('touch', '-h', '-t', '197001010000.00', "$temp/system-28-link") == 0 or die 'touch';
is(generationLabel("$temp/system-28-link"), '28', 'epoch metadata falls back to the generation number');
is(generationLabel("$temp/system-29-link"), '29', 'unavailable metadata falls back to the generation number');
local $ENV{TZ} = "Europe/Moscow";
tzset();
is(generationLabel("$temp/system-5-link"), "5 - 26_11_2026/18:05", "system time zone");
is(generationLabel("$temp/system-5-link", "UTC"), "5 - 26_11_2026/15:05", "configured zone overrides shell TZ");
done_testing;
