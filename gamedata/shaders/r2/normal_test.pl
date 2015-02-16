use strict;
use diagnostics;

sub mul_vec {
	my %mat = %{$_[0]};
	my @vec = @{$_[1]};
	my @ret;
	for (my $i = 1; $i < 4; $i++) {
		push @ret, ($mat{$i}->[0]*$vec[0] + $mat{$i}->[1]*$vec[1] + $mat{$i}->[2]*$vec[2]);
	}
	return @ret;
}

my %dots = (
	1 => [-0.692, -0.598, 0],
	2 => [-0.500,  0.457, 0],
	3 => [ 0.185, -0.893, 0],
	4 => [ 0.610,  0.767, 0],
);
my @N = (-0.5,-0.4,-0.768);
my $l = sqrt($N[0]*$N[0] + $N[1]*$N[1]);
my @cross = ($N[1]/$l, -$N[0]/$l, 0);
my $dot = -$N[2];
my $sin = sqrt(1-$dot*$dot);
my %mat = (
	1 => [			$dot + (1-$dot)*$cross[0]*$cross[0], (1-$dot)*$cross[0]*$cross[1] - $sin*$cross[2], (1-$dot)*$cross[0]*$cross[2] + $sin*$cross[1]],
	2 => [(1-$dot)*$cross[0]*$cross[1] + $sin*$cross[2],		   $dot + (1-$dot)*$cross[1]*$cross[1], (1-$dot)*$cross[1]*$cross[2] - $sin*$cross[0]],
	3 => [(1-$dot)*$cross[0]*$cross[2] - $sin*$cross[1], (1-$dot)*$cross[1]*$cross[2] + $sin*$cross[0], 		  $dot + (1-$dot)*$cross[2]*$cross[2]],
);
foreach my $k (keys %dots) {
	my @dot = @{$dots{$k}};
	my @sample = mul_vec(\%mat,\@dot);
	print "$k: ".join(',',@sample)."\n";
}
print "done!\n";