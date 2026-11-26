use strict;
use warnings;
use File::Basename qw(basename dirname);
use Cwd qw(abs_path);
use POSIX qw(strftime tzset);

sub generationLabel {
    my ($path, $zone) = @_;
    my ($number) = basename($path) =~ /-(\d+)-link\z/;
    my @stat = lstat($path);
    return undef if !defined($number) || !@stat || !-l _;
    local $ENV{TZ} = $zone if defined($zone) && length($zone);
    tzset();
    return "$number - " . strftime("%d_%m_%Y/%H:%M", localtime($stat[9]));
}

sub currentGenerationLabel {
    my ($profile, $configuration, $zone) = @_;
    my $current = readlink($profile) // return undef;
    my $name = basename($profile);
    return undef unless basename($current) =~ /^\Q$name\E-\d+-link\z/;
    my $link = dirname($profile) . "/" . basename($current);
    my $selected = abs_path($link) // return undef;
    return undef unless $selected eq (abs_path($configuration) // "");
    return generationLabel($link, $zone);
}

1;
