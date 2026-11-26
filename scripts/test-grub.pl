use strict;
use warnings;
use File::Temp qw(tempdir);
use POSIX qw(tzset);
use Test::More;

require $ARGV[0];
my $temp = tempdir(CLEANUP => 1);
mkdir "$temp/store";
mkdir "$temp/other";
local $ENV{TZ} = "UTC";
tzset();
for my $i (1 .. 20) {
    my $link = "$temp/system-$i-link";
    symlink("$temp/store", $link) or die $!;
    system("touch", "-h", "-t", sprintf("2026112615%02d.00", $i), $link) == 0 or die "touch";
    is(generationLabel($link), sprintf("%d - 26_11_2026/15:%02d", $i, $i), "real time of generation $i");
}
symlink("system-5-link", "$temp/system") or die $!;
is(currentGenerationLabel("$temp/system", "$temp/store"), "5 - 26_11_2026/15:05", "current generation");
is(currentGenerationLabel("$temp/system", "$temp/other"), undef, "unknown system falls back");
is(generationLabel("$temp/system-21-link"), undef, "missing link");
local $ENV{TZ} = "Europe/Moscow";
tzset();
is(generationLabel("$temp/system-5-link"), "5 - 26_11_2026/18:05", "system time zone");
is(generationLabel("$temp/system-5-link", "UTC"), "5 - 26_11_2026/15:05", "configured zone overrides shell TZ");
done_testing;
