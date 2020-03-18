# S.T.A.L.K.E.R. gamemtl.xr compiler/decompiler
# Update history:
# 	30/08/2012 - refactoring
##############################################
use strict;
use Getopt::Long;
use stkutils::chunked;
use stkutils::debug qw(fail warn STDERR_CONSOLE STDOUT_CONSOLE STDERR_FILE STDOUT_FILE);
use stkutils::xr::gamemtl_xr;

# handle signals
$SIG{__WARN__} = sub{warn(@_);};

# parsing command line
my ($src, $out, $mode, $log);
GetOptions(
	# main options
	'decompile:s' => \&process,
	'compile:s' => \&process,
	# common options
	'out=s' => \$out,
	'log:s' => \$log,
) or die usage();

# initializing debug
my $debug_mode = STDERR_CONSOLE|STDOUT_CONSOLE;
$debug_mode = STDERR_FILE|STDOUT_FILE if defined $log;
$log = 'gmxrcdc.log' if defined $log && ($log eq '');
my $debug = stkutils::debug->new($debug_mode, $log);

# start processing
SWITCH: {
	($mode eq 'decompile') && do {decompile(); last SWITCH;};
	($mode eq 'compile') && do {compile(); last SWITCH;};
}

print "done!\n";
$debug->DESTROY();

sub usage {
	print "gamemtl.xr compiler/decompiler\n";
	print "Usage:\n";
	print "decompile:	gmxrcdc.pl -d <filename> [-out <path> -log <log_filename>]\n";
	print "compile:	gmxrcdc.pl -c <path> [-out <filename> -log <log_filename>]\n";
}
sub process {
	$mode = $_[0];
	$src = $_[1];
}
sub decompile {
	$src = 'gamemtl.xr' if $src eq '';
	
	print "opening $src\n";
	my $fh = stkutils::chunked->new($src, 'r') or fail("$!: $src\n");
	my $pxr = stkutils::xr::gamemtl_xr->new();
	$pxr->read($fh);
	$pxr->export($out);
	$fh->close();
}
sub compile {
	$out = 'gamemtl.xr.new' if (!defined $out or ($out eq ''));
	
	print "opening $src\n";
	my $fh = stkutils::chunked->new($out, 'w') or fail("$!: $out\n");
	my $pxr = stkutils::xr::gamemtl_xr->new();
	$pxr->my_import($src);
	$pxr->write($fh);
	$fh->close();
}