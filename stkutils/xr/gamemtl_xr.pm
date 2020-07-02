# S.T.A.L.K.E.R. gamemtl.xr handling module
# Update history: 
#	30/08/2012 - initial release
##############################################
package stkutils::xr::gamemtl_xr;
use strict;
use stkutils::data_packet;
use stkutils::ini_file;
use stkutils::debug qw(fail warn);
use stkutils::utils qw(get_filelist);
use File::Path;

use constant GAMEMTLS_CHUNK_VERSION 		=> 0x1000;
use constant GAMEMTLS_CHUNK_AUTOINC 		=> 0x1001;
use constant GAMEMTLS_CHUNK_MATERIALS		=> 0x1002;
use constant GAMEMTLS_CHUNK_MATERIAL_PAIRS	=> 0x1003;

sub new {
	my $class = shift;
	my $self = {};
	bless $self, $class;
	return $self;
}
sub read {
	my $self = shift;
	my ($CDH) = @_;
	print "reading...\n";
	while (1) {
		my ($index, $size) = $CDH->r_chunk_open();
		defined $index or last;
		SWITCH: {
			$index == GAMEMTLS_CHUNK_VERSION && do{$self->read_version($CDH);last SWITCH;};
			$index == GAMEMTLS_CHUNK_AUTOINC && do{$self->read_autoinc($CDH);last SWITCH;};
			$index == GAMEMTLS_CHUNK_MATERIALS && do{$self->read_materials($CDH);last SWITCH;};
			$index == GAMEMTLS_CHUNK_MATERIAL_PAIRS && do{$self->read_material_pairs($CDH);last SWITCH;};
			fail('unknown chunk index '.$index);
		}
		$CDH->r_chunk_close();
	}
	$CDH->close();
}
sub read_version {
	my $self = shift;
	my ($CDH) = @_;	
	print "	version\n";
	$self->{version} = unpack('v', ${$CDH->r_chunk_data()});
	fail('unsupported version '.$self->{version}) unless $self->{version} == 1;
}
sub read_autoinc {
	my $self = shift;
	my ($CDH) = @_;	
	print "	autoinc\n";
	($self->{material_index}, $self->{material_pair_index}) = unpack ('VV', ${$CDH->r_chunk_data()});
}
sub read_materials {
	my $self = shift;
	my ($CDH) = @_;	
	print "	materials\n";
	while (1) {
		my ($index, $size) = $CDH->r_chunk_open();
		defined $index or last;
		my $mat = material->new();
		$mat->read($CDH);
		push @{$self->{materials}}, $mat;
		$CDH->r_chunk_close();
	}
}
sub read_material_pairs {
	my $self = shift;
	my ($CDH) = @_;	
	print "	material pairs\n";
	while (1) {
		my ($index, $size) = $CDH->r_chunk_open();
		defined $index or last;
		my $mat_p = material_pairs->new();
		$mat_p->read($CDH);
		push @{$self->{material_pairs}}, $mat_p;
		$CDH->r_chunk_close();
	}
}
sub write {
	my $self = shift;
	my ($CDH) = @_;
	print "writing...\n";
		
	$self->subst_mat_names();
	$self->write_version($CDH);
	$self->write_autoinc($CDH);
	$self->write_materials($CDH);
	$self->write_material_pairs($CDH);
}
sub write_version {
	my $self = shift;
	my ($CDH) = @_;	
	print "	version\n";
	$CDH->w_chunk(GAMEMTLS_CHUNK_VERSION, pack('v', $self->{version}));
}
sub write_autoinc {
	my $self = shift;
	my ($CDH) = @_;	
	print "	autoinc\n";
	$CDH->w_chunk(GAMEMTLS_CHUNK_AUTOINC, pack('VV', $self->{material_index}, $self->{material_pair_index}));
}
sub write_materials {
	my $self = shift;
	my ($CDH) = @_;	
	print "	materials\n";
	$CDH->w_chunk_open(GAMEMTLS_CHUNK_MATERIALS);
	my $i = 0;
	foreach my $mat (@{$self->{materials}}) {
		$mat->write($CDH, $i++);
	}
	$CDH->w_chunk_close();
}
sub write_material_pairs {
	my $self = shift;
	my ($CDH) = @_;	
	print "	material pairs\n";
	$CDH->w_chunk_open(GAMEMTLS_CHUNK_MATERIAL_PAIRS);
	my $i = 0;
	foreach my $mat_p (@{$self->{material_pairs}}) {
		$mat_p->write($CDH, $i++);
	}
	$CDH->w_chunk_close();
}
sub export {
	my $self = shift;
	my ($folder) = @_;
	print "exporting...\n";
	File::Path::mkpath($folder, 0);
	chdir $folder or fail('cannot change dir to '.$folder);
	
	my $ini = IO::File->new('game_materials.ltx', 'w') or fail("game_materials.ltx: $!\n");
	print $ini "[general]\n";
	print $ini "version = $self->{version}\n";
	print $ini "material_index = $self->{material_index}\n";
	print $ini "material_pair_index = $self->{material_pair_index}\n";
	$ini->close();
	
	$self->subst_mat_ids();
	$self->export_materials();
	$self->export_material_pairs();
}
sub export_materials {
	my $self = shift;
	print "	materials\n";
	foreach my $mat (@{$self->{materials}}) {
		$mat->export();
	}
}
sub export_material_pairs {
	my $self = shift;
	print "	material pairs\n";
	foreach my $mat_p (@{$self->{material_pairs}}) {
		$mat_p->export();
	}
}
sub my_import {
	my $self = shift;
	my ($folder) = @_;
	print "importing...\n";
	my $ini = stkutils::ini_file->new($folder.'game_materials.ltx', 'r') or fail("game_materials.ltx: $!\n");
	$self->{version} = $ini->value('general', 'version');
	$self->{material_index} = $ini->value('general', 'material_index');
	$self->{material_pair_index} = $ini->value('general', 'material_pair_index');
	$ini->close();
	
	$self->import_materials($folder);
	$self->import_material_pairs($folder);
}
sub import_materials {
	my $self = shift;
	my ($folder) = @_;
	print "	materials\n";
	my $mats = get_filelist($folder.'\MATERIALS', 'ltx');
	
	foreach my $path (@$mats) {
		my $mat = material->new();
		$mat->import($path);
		push @{$self->{materials}}, $mat;
	}	
	$self->{ materials } = [
	  sort { $a->{ ID } <=> $b->{ ID } } @{ $self->{ materials } }
	];
	$self->{ material_index } = $self->{ materials }->[ -1 ]->{ ID } + 1;
}
sub import_material_pairs {
	my $self = shift;
	my ($folder, $mode) = @_;
	print "	material pairs\n";
	my $mat_ps = get_filelist($folder.'\MATERIAL_PAIRS', 'ltx');
	
	foreach my $path (@$mat_ps) {
		my $mat_p = material_pairs->new();
		$mat_p->import($path);
		push @{$self->{material_pairs}}, $mat_p;
	}	
	$self->{ material_pairs } = [
	  sort { $a->{ ID } <=> $b->{ ID } } @{ $self->{ material_pairs } }
	];
	$self->{ material_pair_index } = $self->{ material_pairs }->[ -1 ]->{ ID } + 1;
}
sub subst_mat_ids {
	my $self = shift;
	
	my %mtl_by_id = ();
	foreach my $mat (@{$self->{materials}}) {
		$mtl_by_id{$mat->{ID}} = $mat->{m_Name};
	}
	foreach my $mat_p (@{$self->{material_pairs}}) {
		$mat_p->{mtl0} = $mtl_by_id{$mat_p->{mtl0}};
		$mat_p->{mtl1} = $mtl_by_id{$mat_p->{mtl1}};
	}
}
sub subst_mat_names {
	my $self = shift;
	
	my %mtl_by_name = ();
	foreach my $mat (@{$self->{materials}}) {
		$mtl_by_name{$mat->{m_Name}} = $mat->{ID};
	}
	foreach my $mat_p (@{$self->{material_pairs}}) {
		$mat_p->{mtl0} = $mtl_by_name{$mat_p->{mtl0}};
		$mat_p->{mtl1} = $mtl_by_name{$mat_p->{mtl1}};
	}
}
#######################################################################
package material;
use strict;
use stkutils::debug qw(fail);

use constant GAMEMTL_CHUNK_MAIN => 0x1000;
use constant GAMEMTL_CHUNK_FLAGS => 0x1001;
use constant GAMEMTL_CHUNK_PHYSICS => 0x1002;
use constant GAMEMTL_CHUNK_FACTORS => 0x1003;
use constant GAMEMTL_CHUNK_FLOTATION => 0x1004;
use constant GAMEMTL_CHUNK_DESC => 0x1005;
use constant GAMEMTL_CHUNK_INJURY => 0x1006;
use constant GAMEMTL_CHUNK_DENSITY => 0x1007;
use constant GAMEMTL_CHUNK_SHOOTING => 0x1008;

use constant mflags => (
	{name => 'MF_BREAKABLE', 			value	=> 0x1},
	{name => 'MF_UNK_0x2', 				value	=> 0x2},
	{name => 'MF_BOUNCEABLE',			value	=> 0x4},
	{name => 'MF_SKIDMARK', 			value	=> 0x8},
	{name => 'MF_BLOODMARK', 			value	=> 0x10},
	{name => 'MF_CLIMABLE', 			value	=> 0x20},
	{name => 'MF_UNK_0x40', 			value	=> 0x40},
	{name => 'MF_PASSABLE', 			value	=> 0x80},
	
	{name => 'MF_DYNAMIC', 				value	=> 0x100},
	{name => 'MF_LIQUID', 				value	=> 0x200},
	{name => 'MF_SUPPRESS_SHADOW', 		value	=> 0x400},
	{name => 'MF_SUPPRESS_WALLMARKS', 	value	=> 0x800},
	{name => 'MF_ACTOR_OBSTACLE', 		value	=> 0x1000},
	{name => 'MF_BULLET_NO_RICOSHET', 	value	=> 0x2000},
	{name => 'MF_PICKABLE', 		value	=> 0x4000},
	{name => 'MF_OUTDOOR', 			value	=> 0x8000},
	
	{name => 'MF_INJURIOUS', 			value	=> 0x10000000},
	{name => 'MF_SHOOTABLE', 			value	=> 0x20000000},
	{name => 'MF_TRANSPARENT', 			value	=> 0x40000000},
	{name => 'MF_SLOW_DOWN', 			value	=> 0x80000000},
);

sub new {
	my $class = shift;
	my $self = {};
	$self->{service_flags} = 0;
	$self->{data} = '';
	$self->{data} = $_[0] if $#_ == 0;
	bless $self, $class;
	return $self;
}
sub read {
	my $self = shift;
	my ($CDH) = @_;
	while (1) {
		my ($index, $size) = $CDH->r_chunk_open();
		defined $index or last;
		SWITCH: {
			$index == GAMEMTL_CHUNK_MAIN && do{($self->{ID}, $self->{m_Name}) = unpack('VZ*', ${$CDH->r_chunk_data()});last SWITCH;};
			$index == GAMEMTL_CHUNK_FLAGS && do{$self->{m_Flags} = unpack('V', ${$CDH->r_chunk_data()});last SWITCH;};
			$index == GAMEMTL_CHUNK_PHYSICS && do{
				($self->{fPHFriction}, $self->{fPHDamping}, $self->{fPHSpring}, $self->{fPHBounceStartVelocity}, $self->{fPHBouncing}) = unpack('f5', ${$CDH->r_chunk_data()});last SWITCH;};
			$index == GAMEMTL_CHUNK_FACTORS && do{
				($self->{fShootFactor}, $self->{fBounceDamageFactor}, $self->{fVisTransparencyFactor}, $self->{fSndOcclusionFactor}) = unpack('f4', ${$CDH->r_chunk_data()});last SWITCH;};
			$index == GAMEMTL_CHUNK_FLOTATION && do{$self->{fFlotationFactor} = unpack('f', ${$CDH->r_chunk_data()});last SWITCH;};
			$index == GAMEMTL_CHUNK_DESC && do{$self->{m_Desc} = unpack('Z*', ${$CDH->r_chunk_data()});last SWITCH;};
			$index == GAMEMTL_CHUNK_INJURY && do{$self->{fInjuriousSpeed} = unpack('f', ${$CDH->r_chunk_data()});last SWITCH;};
			$index == GAMEMTL_CHUNK_DENSITY && do{$self->{fDensityFactor} = unpack('f', ${$CDH->r_chunk_data()});last SWITCH;};
			$index == GAMEMTL_CHUNK_SHOOTING && do{$self->{fShootingMP} = unpack('f', ${$CDH->r_chunk_data()});last SWITCH;};
			fail('unknown chunk index '.$index);
		}
		$CDH->r_chunk_close();
	}
}
sub write {
	my $self = shift;
	my ($CDH, $index) = @_;
	
	$CDH->w_chunk_open($index);
	$CDH->w_chunk(GAMEMTL_CHUNK_MAIN, pack('VZ*', $self->{ID}, $self->{m_Name}));
	$CDH->w_chunk(GAMEMTL_CHUNK_DESC, pack('Z*', $self->{m_Desc})) if defined $self->{m_Desc};
	$CDH->w_chunk(GAMEMTL_CHUNK_FLAGS, pack('V', $self->{m_Flags}));
	$CDH->w_chunk(GAMEMTL_CHUNK_PHYSICS, pack('f5', $self->{fPHFriction}, $self->{fPHDamping}, $self->{fPHSpring}, $self->{fPHBounceStartVelocity}, $self->{fPHBouncing}));
	$CDH->w_chunk(GAMEMTL_CHUNK_FACTORS, pack('f4', $self->{fShootFactor}, $self->{fBounceDamageFactor}, $self->{fVisTransparencyFactor}, $self->{fSndOcclusionFactor}));
	$CDH->w_chunk(GAMEMTL_CHUNK_SHOOTING, pack('f', $self->{fShootingMP})) if defined $self->{fShootingMP};
	$CDH->w_chunk(GAMEMTL_CHUNK_FLOTATION, pack('f', $self->{fFlotationFactor})) if defined $self->{fFlotationFactor};
	$CDH->w_chunk(GAMEMTL_CHUNK_INJURY, pack('f', $self->{fInjuriousSpeed})) if defined $self->{fInjuriousSpeed};
	$CDH->w_chunk(GAMEMTL_CHUNK_DENSITY, pack('f', $self->{fDensityFactor})) if defined $self->{fDensityFactor};
	$CDH->w_chunk_close();
}
sub export {
	my $self = shift;
	
	File::Path::mkpath('MATERIALS', 0);
	my @path = split(/\\/, $self->{m_Name});
	pop @path;
	my $path = join('\\', @path);  	
	if ($path && $path ne '') {
		File::Path::mkpath('MATERIALS\\'.$path, 0);
	}
	
	my $fn = 'MATERIALS\\'.$self->{m_Name}.'.ltx';
	my $bin_fh = IO::File->new($fn, 'w') or fail("$fn: $!\n");
	print $bin_fh "[general]\n";
	print $bin_fh "id = $self->{ID}\n";
	print $bin_fh "name = $self->{m_Name}\n";
	print $bin_fh "description = $self->{m_Desc}\n";			#added in build 1623
	print $bin_fh "\n[flags]\n";
	$self->set_flags();
	print $bin_fh "flags = $self->{m_Flags}\n";
	print $bin_fh "\n[physics]\n";
	printf $bin_fh "fPHFriction = %.5g\n", $self->{fPHFriction};
	printf $bin_fh "fPHDamping = %.5g\n", $self->{fPHDamping};
	printf $bin_fh "fPHSpring = %.5g\n", $self->{fPHSpring};
	printf $bin_fh "fPHBounceStartVelocity = %.5g\n", $self->{fPHBounceStartVelocity};
	printf $bin_fh "fPHBouncing = %.5g\n", $self->{fPHBouncing};
	print $bin_fh "\n[factors]\n";
	printf $bin_fh "fShootFactor = %.5g\n", $self->{fShootFactor};
	printf $bin_fh "fBounceDamageFactor = %.5g\n", $self->{fBounceDamageFactor};
	printf $bin_fh "fVisTransparencyFactor = %.5g\n", $self->{fVisTransparencyFactor};
	printf $bin_fh "fSndOcclusionFactor = %.5g\n", $self->{fSndOcclusionFactor};
	printf $bin_fh "fShootingMP = %.5g\n", $self->{fShootingMP} if defined $self->{fShootingMP}; #added in Call Of Pripyat
	printf $bin_fh "fFlotationFactor = %.5g\n", $self->{fFlotationFactor} if defined $self->{fFlotationFactor}; #added in build 1623
	printf $bin_fh "fInjuriousSpeed = %.5g\n", $self->{fInjuriousSpeed} if defined $self->{fInjuriousSpeed}; #added in build 2205
	printf $bin_fh "fDensityFactor = %.5g\n\n", $self->{fDensityFactor} if defined $self->{fDensityFactor};  #added in Clear Sky
	$bin_fh->close();
}
sub import {
	my $self = shift;
	my ($src) = @_;
	
	my $cf = stkutils::ini_file->new($src, 'r') or fail("$src: $!\n");
	$self->{ID} = $cf->value('general', 'id') + 0;
	$self->{m_Name} = $cf->value('general', 'name');
	$self->{m_Desc} = $cf->value('general', 'description');
	$self->{m_Flags} = $cf->value('flags', 'flags');
	$self->get_flags();
	$self->{fPHFriction} = $cf->value('physics', 'fPHFriction');
	$self->{fPHDamping} = $cf->value('physics', 'fPHDamping');
	$self->{fPHSpring} = $cf->value('physics', 'fPHSpring');
	$self->{fPHBounceStartVelocity} = $cf->value('physics', 'fPHBounceStartVelocity');
	$self->{fPHBouncing} = $cf->value('physics', 'fPHBouncing');
	$self->{fShootFactor} = $cf->value('factors', 'fShootFactor');
	$self->{fBounceDamageFactor} = $cf->value('factors', 'fBounceDamageFactor');
	$self->{fVisTransparencyFactor} = $cf->value('factors', 'fVisTransparencyFactor');
	$self->{fSndOcclusionFactor} = $cf->value('factors', 'fSndOcclusionFactor');
	$self->{fShootingMP} = $cf->value('factors', 'fShootingMP');
	$self->{fFlotationFactor} = $cf->value('factors', 'fFlotationFactor');
	$self->{fInjuriousSpeed} = $cf->value('factors', 'fInjuriousSpeed');
	$self->{fDensityFactor} = $cf->value('factors', 'fDensityFactor');	
	$cf->close();
}
sub get_flags {
	my $self = shift;

	my @temp = split /,\s*/, $self->{m_Flags};
	my $ftemp = 0;
	foreach my $fl (@temp) {
		foreach my $k (mflags) {
			if ($k->{name} eq $fl) {
				$ftemp += $k->{value};
			}
		}
	}
	$self->{m_Flags} = $ftemp;
}
sub set_flags {
	my $self = shift;
	
	my $temp = '';
	foreach my $k (mflags) {
		if (($self->{m_Flags} & $k->{value}) == $k->{value}) {
			$temp .= $k->{name};
			$temp .= ',';
			$self->{m_Flags} -= $k->{value};
		}
	}
	if ($self->{m_Flags} != 0)	{printf "%#x\n", $self->{m_Flags}; fail("some flags left\n")};
	$self->{m_Flags} = substr($temp, 0, -1);
}
#######################################################################
package material_pairs;
use strict;
use stkutils::debug qw(fail);

use constant GAMEMTLPAIR_CHUNK_PAIR => 0x1000;
use constant GAMEMTLPAIR_CHUNK_1616_1 => 0x1001;
use constant GAMEMTLPAIR_CHUNK_BREAKING => 0x1002;
use constant GAMEMTLPAIR_CHUNK_STEP => 0x1003;
use constant GAMEMTLPAIR_CHUNK_1616_2 => 0x1004;
use constant GAMEMTLPAIR_CHUNK_COLLIDE => 0x1005;

use constant mflags => (
	{name => 'MPF_BREAKING_SOUNDS', value	=> 0x2},
	{name => 'MPF_STEP_SOUNDS', value	=> 0x4},
	{name => 'MPF_COLLIDE_SOUNDS', value	=> 0x10},
	{name => 'MPF_COLLIDE_PARTICLES', value	=> 0x20},
	{name => 'MPF_COLLIDE_MARKS', value	=> 0x40},
);

sub new {
	my $class = shift;
	my $self = {};
	$self->{data} = '';
	$self->{data} = $_[0] if $#_ == 0;
	bless $self, $class;
	return $self;
}
sub read {
	my $self = shift;
	my ($CDH) = @_;	
	
	while (1) {
		my ($index, $size) = $CDH->r_chunk_open();
		defined $index or last;	
		SWITCH: {
			$index == GAMEMTLPAIR_CHUNK_PAIR && do{($self->{mtl0}, $self->{mtl1}, $self->{ID}, $self->{ID_parent}, $self->{OwnProps}) = unpack('V5', ${$CDH->r_chunk_data()});last SWITCH;};
			$index == GAMEMTLPAIR_CHUNK_1616_1 && do{$self->{unk_1} = unpack('V', ${$CDH->r_chunk_data()});last SWITCH;};
			$index == GAMEMTLPAIR_CHUNK_BREAKING && do{$self->{BreakingSounds} = unpack('Z*', ${$CDH->r_chunk_data()});last SWITCH;};
			$index == GAMEMTLPAIR_CHUNK_STEP && do{$self->{StepSounds} = unpack('Z*', ${$CDH->r_chunk_data()});last SWITCH;};
			$index == GAMEMTLPAIR_CHUNK_1616_2 && do{$self->{unk_2} = unpack('Z*', ${$CDH->r_chunk_data()});last SWITCH;};
			$index == GAMEMTLPAIR_CHUNK_COLLIDE && do{($self->{CollideSounds}, $self->{CollideParticles}, $self->{CollideMarks}) = unpack('Z*Z*Z*', ${$CDH->r_chunk_data()});last SWITCH;};
			fail('unknown chunk index '.$index);
		}
		$CDH->r_chunk_close();
	}
}
sub write {
	my $self = shift;
	my ($CDH, $index) = @_;
	
	$CDH->w_chunk_open($index);
	$CDH->w_chunk(GAMEMTLPAIR_CHUNK_PAIR, pack('V5', $self->{mtl0}, $self->{mtl1}, $self->{ID}, $self->{ID_parent}, $self->{OwnProps}));
	$CDH->w_chunk(GAMEMTLPAIR_CHUNK_1616_1, pack('V', $self->{unk_1})) if defined $self->{unk_1};
	$CDH->w_chunk(GAMEMTLPAIR_CHUNK_BREAKING, pack('Z*', $self->{BreakingSounds}));
	$CDH->w_chunk(GAMEMTLPAIR_CHUNK_STEP, pack('Z*', $self->{StepSounds}));
	$CDH->w_chunk(GAMEMTLPAIR_CHUNK_1616_2, pack('Z*', $self->{unk_2})) if defined $self->{unk_2};
	$CDH->w_chunk(GAMEMTLPAIR_CHUNK_COLLIDE, pack('Z*Z*Z*', $self->{CollideSounds}, $self->{CollideParticles}, $self->{CollideMarks}));
	$CDH->w_chunk_close();
}
sub export {
	my $self = shift;
	my ($mode) = @_;	
	
	File::Path::mkpath('MATERIAL_PAIRS', 0);
	
	my $fn = 'MATERIAL_PAIRS\\'.$self->{ID}.'.ltx';
	my $bin_fh = IO::File->new($fn, 'w') or fail("$fn: $!\n");
	print $bin_fh "[general]\n";
	print $bin_fh "id = $self->{ID}\n";
	if ($self->{ID_parent} == 0xFFFFFFFF) {
		print $bin_fh "parent_id = none\n";
	} else {
		print $bin_fh "parent_id = $self->{ID_parent}\n";
	}
	print $bin_fh "mtl0 = $self->{mtl0}\n";
	print $bin_fh "mtl1 = $self->{mtl1}\n";	
	$self->set_props();
	printf $bin_fh "OwnProps = $self->{OwnProps}\n";
	print $bin_fh "\n[breaking]\n";
	print $bin_fh "BreakingSounds = $self->{BreakingSounds}\n";
	print $bin_fh "\n[step]\n";
	print $bin_fh "StepSounds = $self->{StepSounds}\n";
	print $bin_fh "\n[collide]\n";
	print $bin_fh "CollideSounds = $self->{CollideSounds}\n";
	print $bin_fh "CollideParticles = $self->{CollideParticles}\n";
	print $bin_fh "CollideMarks = $self->{CollideMarks}\n";
	if (defined $self->{unk_1} && defined $self->{unk_2}) {
		print $bin_fh "\n[unk]\n";
		print $bin_fh "unk_1 = $self->{unk_1}\n";
		print $bin_fh "unk_2 = $self->{unk_2}\n";	
	}
	$bin_fh->close();
}
sub import {
	my $self = shift;
	my ($src) = @_;	
	
	my $cf = stkutils::ini_file->new($src, 'r') or fail("$src: $!\n");
	$self->{ID} = $cf->value('general', 'id') + 0;
	$self->{ID_parent} = $cf->value('general', 'parent_id');
	$self->{ID_parent} = 0xFFFFFFFF if ($self->{ID_parent} eq 'none');
	$self->{mtl0} = $cf->value('general', 'mtl0');
	$self->{mtl1} = $cf->value('general', 'mtl1');
	$self->{OwnProps} = $cf->value('general', 'OwnProps');
	$self->get_props();
	$self->{BreakingSounds} = $cf->value('breaking', 'BreakingSounds');
	$self->{StepSounds} = $cf->value('step', 'StepSounds');
	$self->{CollideSounds} = $cf->value('collide', 'CollideSounds');
	$self->{CollideParticles} = $cf->value('collide', 'CollideParticles');
	$self->{CollideMarks} = $cf->value('collide', 'CollideMarks');
	if ($cf->section_exists('unk')) {
		$self->{unk_1} = $cf->value('unk', 'unk_1');
		$self->{unk_2} = $cf->value('unk', 'unk_2');		
	}
	$cf->close();
}
sub get_props {
	my $self = shift;
	
	my $temp = '';
	if ($self->{OwnProps} eq 'none') {
		$self->{OwnProps} = 0xFFFFFFFF;
		return;
	}
	if ($self->{OwnProps} eq 'all') {
		$self->{OwnProps} = 0;
		return;
	}
	my @temp = split /,\s*/, $self->{OwnProps};
	my $ftemp = 0;
	foreach my $fl (@temp) {
		foreach my $k (mflags) {
			if ($k->{name} eq $fl) {
				$ftemp += $k->{value};
			}
		}
	}
	$self->{OwnProps} = $ftemp;
}
sub set_props {
	my $self = shift;
	
	my $temp = '';
	if ($self->{OwnProps} == 0xFFFFFFFF) {
		$self->{OwnProps} = 'none';
		return;
	}
	if ($self->{OwnProps} == 0) {
		$self->{OwnProps} = 'all';
		return;
	}
	if (($self->{OwnProps} & 0xFFFFFFFF) > 0xFF) {
		$self->{OwnProps} &= 0x76;
	}
	foreach my $k (mflags) {
		if (($self->{OwnProps} & $k->{value}) == $k->{value}) {
			$temp .= $k->{name};
			$temp .= ',';
			$self->{OwnProps} -= $k->{value};
		}
	}
	if ($self->{OwnProps} != 0)	{printf "%#x\n", $self->{OwnProps}; fail("some flags left\n")};
	$self->{OwnProps} = substr($temp, 0, -1);
}
#######################################################################
1;