use strict;
use warnings;
use Fcntl qw(S_ISLNK);
use File::Basename qw(basename);
use POSIX qw(strftime tzset);

sub generationLabel {
    my ($path, $zone) = @_;
    my ($number) = basename($path) =~ /-(\d+)-link\z/;
    return undef unless defined($number);
    # install-grub.pl imports File::stat::lstat, which returns one object.
    my @stat = CORE::lstat($path);
    return $number unless @stat && S_ISLNK($stat[2]) && $stat[9] > 0;
    local $ENV{TZ} = $zone if defined($zone) && length($zone);
    tzset();
    return "$number - " . strftime("%d_%m_%Y/%H:%M", localtime($stat[9]));
}

1;
