# Module for packing and unpacking data
# Update history: 
#	26/08/2012 - fix for new fail() syntax
######################################################
package stkutils::data_packet;
use strict;
use IO::File;
use stkutils::debug qw(fail);
use stkutils::ini_file;
use stkutils::math;
use POSIX;
use constant FL_IS_25XX => 0x08;
use constant FL_HANDLED => 0x20;
use constant SUCCESS_HANDLE => 2;
use constant template_len => {
	'V' => 4,
	'v' => 2,
	'C' => 1,
	'l' => 4,
	'f' => 4,
	'vf' => 6,
	'v4' => 8,
	'a[16]' => 16,
	'C8' => 8,
	'C4' => 4,
	'f2' => 8,
	'f3' => 12,
	'f4' => 16,
	'l3' => 12,
	'l4' => 16,
	'V2' => 8,
	'V3' => 12,
	'V4' => 16,	
	'a[12]'	=> 12,
	'a[8]' => 8,
	'a[169]' => 169,
	'a[157]' => 157,
	'a[153]' => 153,
};
use constant template_for_scalar => {
	h8	=> 'C',
	h16	=> 'v',
	h32	=> 'V',
	u8	=> 'C',
	u16	=> 'v',
	u32	=> 'V',
	s8	=> 'C',
	s16	=> 'v',	
	s32	=> 'l',
	q8	=> 'C',
	q16	=> 'v',	
	q16_old	=> 'v',	
	sz	=> 'Z*',
	f32	=> 'f',
	guid	=> 'a[16]',
	ha1	=> 'a[12]',
	ha2	=> 'a[8]',
	dumb_1	=> 'a[169]',
	dumb_2	=> 'a[157]',
	dumb_3	=> 'a[153]',
};
use constant template_for_vector => {
	l8u8v	=> 'C/C',
	l8u16v	=> 'C/v',
	l8u32v	=> 'C/V',
	l8szv	=> 'C/(Z*)',
	l8szbv	=> 'C/(Z*C)',
	l8szu16v	=> 'C/(Z*v)',
	l8u16u8v	=> 'C/(v*C)',
	l8u16u16v	=> 'C/(v*v)',
	l16u16v	=> 'v/v',
	l32u8v	=> 'V/C',
	l32u16v	=> 'V/v',
	l32u32v	=> 'V/V',
	l32szv	=> 'V/(Z*)',
	u8v3	=> 'C3',
	u8v4	=> 'C4',
	u8v8	=> 'C8',
	u32v2	=> 'V2',
	u16v4	=> 'v4',
	f32v2	=> 'f2',
	f32v3	=> 'f3',
	f32v4	=> 'f4',
	s32v3	=> 'l3',
	s32v4	=> 'l4',
	h32v3	=> 'V3',
	h32v4	=> 'V4',	
	q8v3	=> 'C3',
	q8v4	=> 'C4',
	sdir	=> 'vf',
};
#function refs
use constant sub_hash => {
	'convert_q8' 		=> \&convert_q8,
	'convert_q16' 		=> \&convert_q16,
	'convert_q16_old'	=> \&convert_q16_old,
	'convert_u8' 		=> \&convert_u8,
	'convert_u16' 		=> \&convert_u16,
	'convert_u16_old'	=> \&convert_u16_old,
};
#constructor
sub new {
	my $class = shift;
	my $data = shift;
	my $self = {};
	$self->{data} = '';
	$self->{data} = $$data if defined $data;
	$self->{init_length} = CORE::length($self->{data});
	$self->{pos} = 0;
	bless($self, $class);
	return $self;
}
sub DESTROY {
	undef $_[0]->{data};
}
#unpack
sub unpack {
#	my $self = shift;
#	my $template = shift;
	my $fl = 0;
	$fl = 1 if ($_[1] =~ /f/ and $_[1] !~ /Z/);
fail("packet is not defined") if !(defined $_[0]);
fail("there is no data in packet") if !(defined $_[0]->{data});
fail("template is not defined") if !(defined $_[1]);
	my @values;
	if (!defined $_[2]) {
		@values = CORE::unpack($_[1].'a*', substr($_[0]->{data}, $_[0]->{pos}));
		fail("cannot unpack requested data") if $#values == -1;
		$_[0]->{pos} = length($_[0]->{data}) - length(pop(@values));
	} else {
		my $resid = length($_[0]->{data}) - $_[0]->{pos};
		fail ("data [$resid] is shorter than template [$_[2]]") if $_[2] > $resid;
		@values = CORE::unpack($_[1], substr($_[0]->{data}, $_[0]->{pos}, $_[2]));
		$_[0]->{pos} += $_[2];
	}
fail("data container is empty") if !(defined $_[0]->{data});
#print "@values\n";
	if ($fl == 1) {
		foreach my $val (@values) {
			$val = 0 if (isinf($val) || isnan($val));
		}
		$fl = 0;
	}
	return @values;
}
sub unpack_properties {
	my $self = shift;
	my $container = shift;
	foreach my $p (@_) {
#print "$p->{name} = ";
	
		my $template = template_for_scalar->{$p->{type}};
		($p->{type} eq 'sz')			&& do {$self->_unpack_string($container, $p); next;};
		defined $template				&& do {$self->_unpack_scalar($template, $container, $p); last if is_handled($container); next;};
		($p->{type} eq 'u24')			&& do {$self->_unpack_u24($container, $p); next;};
		($p->{type} eq 'shape')			&& do {$self->_unpack_shape($container, $p); next;};
		($p->{type} eq 'skeleton')		&& do {$self->_unpack_skeleton($container, $p); next;};
		($p->{type} eq 'supplies')		&& do {$self->_unpack_supplies($container, $p); next;};
		($p->{type} =~ /afspawns/)		&& do {$self->_unpack_artefact_spawns($container, $p); next;};
		($p->{type} eq 'ordaf')			&& do {$self->_unpack_ordered_artefacts($container, $p); next;};
		($p->{type} eq 'CTime')			&& do {$container->{$p->{name}} = $self->unpack_ctime(); next;};
		($p->{type} eq 'complex_time')	&& do {$container->{$p->{name}} = $self->_unpack_complex_time($container, $p); last if is_handled($container); next;};
		($p->{type} eq 'npc_info')		&& do {$self->_unpack_npc_info($container, $p); next;};
		($p->{type} eq 'sdir')			&& do {$self->_unpack_sdir($container, $p); last if is_handled($container); next;};
		#SOC
		($p->{type} eq 'jobs')			&& do {$self->_unpack_jobs($container, $p); next;};
		#CS
		($p->{type} eq 'covers')		&& do {$self->_unpack_covers($container, $p); next;};
		($p->{type} eq 'squads')		&& do {$self->_unpack_squads($container, $p); next;};
		($p->{type} eq 'sim_squads')	&& do {$self->_unpack_sim_squads($container, $p); next;};
		($p->{type} eq 'inited_tasks')		&& do {$self->_unpack_inited_tasks($container, $p); next;};
		($p->{type} eq 'inited_find_upgrade_tasks')		&& do {$self->_unpack_inited_find_upgrade_tasks($container, $p); next;};
		($p->{type} eq 'rewards')		&& do {$self->_unpack_rewards($container, $p); next;};
		($p->{type} eq 'minigames')		&& do {$self->_unpack_minigames($container, $p); next;};
		#COP
		($p->{type} eq 'times')			&& do {$self->_unpack_times($container, $p); next;};
		$self->_unpack_vector($container, $p);  
		last if is_handled($container);
	}
}
sub _unpack_scalar {
	my ($self, $template, $container, $p) = @_;
	$self->error_handler($container, $template) if (CORE::length($self->data()) == $self->pos() || (defined template_len->{$template} && $self->resid() < template_len->{$template}));
	return if is_handled($container);
	($container->{$p->{name}}) = $self->unpack($template, template_len->{$template});
	if ($p->{type} =~ /q/) {
		my $func = "convert_".$p->{type};
		$container->{$p->{name}} = sub_hash->{$func}($container->{$p->{name}}, -1, 1);
	}
}
sub _unpack_u24 {
	my ($self, $container, $p) = @_;
	($container->{$p->{name}}) = CORE::unpack('V', CORE::pack('CCCC', $self->unpack('C3', 3), 0));
}
sub _unpack_string {
	my ($self, $container, $p) = @_;
	($container->{$p->{name}}) = $self->unpack('Z*');
	chomp $container->{$p->{name}};
	$container->{$p->{name}} =~ s/\r//g;
}
sub _unpack_vector {
	my ($self, $container, $p) = @_;
	my $template = template_for_vector->{$p->{type}};
	$self->error_handler($container, $template) if (CORE::length($self->data()) == $self->pos() || (defined template_len->{$template} && $self->resid() < template_len->{$template}));
	return if is_handled($container);
	@{$container->{$p->{name}}} = $self->unpack($template, template_len->{$template});
	if ($p->{type} =~ /(q\d+)/) {
		my $func = "convert_".$1;
		foreach (@{$container->{$p->{name}}}) {
			$_ = sub_hash->{$func}($_, -1, 1);
		}
	}
}
sub _unpack_sdir {
	my ($self, $container, $p) = @_;
	$self->error_handler($container, 'vf') if (CORE::length($self->data()) == $self->pos() || $self->resid() < 6);
	return if is_handled($container);
	$self->_unpack_dir($container, $p);
	my ($s) = $self->unpack('f', 4);
	$container->{$p->{name}}[0] *= $s;
	$container->{$p->{name}}[1] *= $s;
	$container->{$p->{name}}[2] *= $s;
}
sub _unpack_dir {
	my ($self, $container, $p) = @_;
	my ($t) = $self->unpack('v', 2);
	my ($i, $u, $v);
	my ($x, $y, $z);
	$u = ($t >> 7) & 0x3f;
	$v = $t & 0x7f;
	if ($u + $v >= 0x7f) {
		$u = 0x7f - $u;
		$v = 0x7f - $v;
	}
	$i = $t & 0x1fff;
	$self->_prepare_uv_adjustment();
	$x = $self->{uv_adjustment}[$i] * $u;
	$y = $self->{uv_adjustment}[$i] * $v;
	my $j = 126-$u-$v;
	if ($j == 0) {
		$z = 0.0000000000001;
	} else {
		$z = $self->{uv_adjustment}[$i] * $j;
	}
	$x *= -1 if $t & 0x8000;
	$y *= -1 if $t & 0x4000;
	$z *= -1 if $t & 0x2000;
	@{$container->{$p->{name}}} = ($x, $y, $z);
}
sub _prepare_uv_adjustment {
	my ($i, $u, $v);
	for (my $i = 0; $i < 0x2000; $i++) {
		$u = $i >> 7;
		$v = $i & 0x7f;
		if ($u + $v >= 0x7f) {
			$u = 0x7f - $u;
			$v = 0x7f - $v;
		}
		$_[0]->{uv_adjustment}[$i] = 1.0/sqrt($u*$u + $v*$v + (126-$u-$v)*(126-$u-$v));
	}
}
sub _unpack_shape {
	my ($self, $container, $p) = @_;	
	my ($count) = $self->unpack('C', 1);
	while ($count--) {
		my %shape;
		($shape{type}) = $self->unpack('C', 1);
		if ($shape{type} == 0) {
			@{$shape{sphere}} = $self->unpack('f4', 16);
		} elsif ($shape{type} == 1) {
			@{$shape{box}} = $self->unpack('f12', 48);
		} else {
			fail("shape has undefined type ($shape{type})");
		}
		push @{$container->{$p->{name}}}, \%shape;
	}
}
sub _unpack_skeleton {
	my ($self, $container, $p) = @_;	
	@{$container->{bones_mask}} = $self->unpack('C8', 8);
	($container->{root_bone}) = $self->unpack('v', 2);
	@{$container->{bbox_min}} = $self->unpack('f3', 12);
	@{$container->{bbox_max}} = $self->unpack('f3', 12);
	my ($count) = $self->unpack('v', 2);
	while ($count--) {
		my %bone;
		@{$bone{ph_position}} = $self->unpack('C3', 3);
		my $i = 0;
		foreach (@{$bone{ph_position}}) {
			$_ = convert_q8($_, $container->{bbox_min}[$i], $container->{bbox_max}[$i]);
			$i++;
		}
		@{$bone{ph_rotation}} = $self->unpack('C4', 4);
		foreach (@{$bone{ph_rotation}}) {
			$_ = convert_q8($_, -1, 1);
		}
		($bone{enabled}) = $self->unpack('C', 1);
		push @{$container->{bones}}, \%bone;
	}
}
sub _unpack_supplies {
	my ($self, $container, $p) = @_;
	my ($count) = $self->unpack('V', 4);
	while ($count--) {
		my $obj = {};
		($obj->{section_name}) = $self->unpack('Z*');
		($obj->{item_count}, $obj->{min_factor}, $obj->{max_factor}) = $self->unpack('Vff', 12);
		push @{$container->{$p->{name}}}, $obj;
	}
}
sub _unpack_artefact_spawns {
	my ($self, $container, $p) = @_;
	my ($count) = $self->unpack('v', 2);
	while ($count--) {
		my $obj = {};
		($obj->{section_name}) = $self->unpack('Z*');
		if ($p->{type} eq 'afspawns') {
			($obj->{weight}) = $self->unpack('f', 4);
		} else {
			($obj->{weight}) = $self->unpack('V', 4);
		}
		push @{$container->{$p->{name}}}, $obj;
	}
}
sub _unpack_ordered_artefacts {
	my ($self, $container, $p) = @_;
	my ($count) = $self->unpack('V', 4);
	while ($count--) {
		my $obj = {};
		($obj->{unknown_string}) = $self->unpack('Z*');
		($obj->{unknown_number}) = $self->unpack('V', 4);
		my ($inner_count) = $self->unpack('V', 4);
		while ($inner_count--) {
			my $afs = {}; 
			($afs->{artefact_name}) = $self->unpack('Z*');
			($afs->{number_1}, 
			$afs->{number_2}) = $self->unpack('VV', 8);
			push @{$obj->{af_sects}}, $afs;
		}
		push @{$container->{$p->{name}}}, $obj;
	}
}
sub unpack_ctime {
	my ($self) = @_;
	my $time = stkutils::math->create('CTime');
	my ($year) = $self->unpack('C', 1);
	if ($year != 0 && $year != 255) {
		$time->set($year, $self->unpack('C5v', 7))
	} else {
		$time->set($year);
	}
	return $time;
}
sub _unpack_complex_time {
	my ($self, $container, $p) = @_;
	$self->error_handler($container, 'C') if (CORE::length($self->data()) == $self->pos() || ($self->resid() < 1));
	return if is_handled($container);
	my ($flag) = $self->unpack('C', 1);
	if ($flag != 0) {
		return $self->unpack_ctime()
	} else {
		return 0;
	}
}
sub _unpack_jobs {
	my ($self, $container, $p) = @_;
	my ($count) = $self->unpack('C', 1);
	while($count--) {
		my $job = {};
		($job->{job_begin},
		$job->{job_fill_idle},
		$job->{job_idle_after_death_end}) = $self->unpack('VVV', 12);
		push @{$container->{$p->{name}}}, $job;
	}
}
sub	_unpack_npc_info {
	my $self = shift;
	if ($_[0]->{version} >= 122) {
		$self->_unpack_npc_info_cop(@_);
	} elsif ($_[0]->{version} >= 117) {
		$self->_unpack_npc_info_soc(@_);
	} else {
		$self->_unpack_npc_info_old(@_);
	}
}
sub _unpack_npc_info_old {
	my ($self, $container, $p) = @_;
	my ($count) = $self->unpack('C', 1);
	while($count--) {
		my %info;
		($info{o_id},
		$info{group},
		$info{squad},
		$info{move_offline},
		$info{switch_offline}) = $self->unpack('vCCCC', 6);
		$info{stay_end} = $self->unpack_ctime();
		($info{jobN}) = $self->unpack('C', 1) if $container->{script_version} >= 1 && $container->{gulagN} != 0;
		push @{$container->{$p->{name}}}, \%info;
	}
}
sub _unpack_npc_info_soc {
	my ($self, $container, $p) = @_;
	my ($count) = $self->unpack('C', 1);
	while($count--) {
		my %info;
		($info{o_id},
		$info{o_group},
		$info{o_squad},
		$info{exclusive}) = $self->unpack('vCCC', 5);
		$info{stay_end} = $self->unpack_ctime();
		($info{Object_begin_job}) = $self->unpack('C', 1);
		($info{Object_didnt_begin_job}) = $self->unpack('C', 1) if $container->{script_version} > 4;
		($info{jobN}) = $self->unpack('C', 1);
		push @{$container->{$p->{name}}}, \%info;
	}
}
sub _unpack_npc_info_cop {
	my ($self, $container, $p) = @_;
	my ($count) = $self->unpack('C', 1);
	while($count--) {
		my %info;
		($info{id},
		$info{job_prior},
		$info{job_id},
		$info{begin_job},
		$info{need_job}) = $self->unpack('vCCCZ*');
		push @{$container->{$p->{name}}}, \%info;
	}
}
sub _unpack_covers {
	my ($self, $container, $p) = @_;
	my ($count) = $self->unpack('C', 1);
	while($count--) {
		my %cover;
		($cover{npc_id},
		$cover{cover_vertex_id}) = $self->unpack('vV', 6);
		@{$cover{cover_position}} = $self->unpack('f3', 12);
		@{$cover{look_pos}} = $self->unpack('f3', 12);
		($cover{is_smart_cover}) = $self->unpack('C', 1);
		push @{$container->{$p->{name}}}, \%cover;
	}
}
sub _unpack_squads {
	my ($self, $container, $p) = @_;
	my ($count) = $self->unpack('C', 1);
	while($count--) {
		my %squad;
		($squad{squad_name},
		$squad{squad_stage},
		$squad{squad_prepare_shouted},
		$squad{squad_attack_shouted},
		$squad{squad_attack_squad}) = $self->unpack('Z*Z*CCC');
		$squad{squad_inited_defend_time} = $self->_unpack_complex_time();
		$squad{squad_start_attack_wait} = $self->_unpack_complex_time();
		$squad{squad_last_defence_kill_time} = $self->_unpack_complex_time();
		($squad{squad_power}) = $self->unpack('f', 4);
		push @{$container->{$p->{name}}}, \%squad;
	}
}
sub _unpack_sim_squads {
	my ($self, $container, $p) = @_;
	my ($count) = $self->unpack('v', 2);
	while($count--) {
		my $squad = {};
		($squad->{squad_id},
		$squad->{settings_id},
		$squad->{is_scripted}) = $self->unpack('Z*Z*C');
		$self->_unpack_sim_squad_generic($container, $squad);
		if ($squad->{is_scripted} == 1) {
			$self->set_save_marker($container, 'load', 0, 'sim_squad_scripted');
			($squad->{next_target},
			$squad->{need_free_update},
			$squad->{relationship},
			$squad->{sympathy}) = $self->unpack('CCCC', 4);			
			$self->set_save_marker($container, 'load', 1, 'sim_squad_scripted');
		}
		push @{$container->{$p->{name}}}, $squad;
	}
}
sub _unpack_sim_squad_generic {
	my ($self, $container, $squad) = @_;
	$self->set_save_marker($container, 'load', 0, 'sim_squad_generic');
	($squad->{smart_id},
	$squad->{assigned_target_smart_id},
	$squad->{sim_combat_id},
	$squad->{delayed_attack_task}) = $self->unpack('vvvv', 8);			
	@{$squad->{random_tasks}} = $self->unpack('C/(vv)');		
	($squad->{npc_count},
	$squad->{squad_power},
	$squad->{commander_id}) = $self->unpack('Cfv', 7);		
	@{$squad->{squad_npc}} = $self->unpack('C/v');	
	($squad->{spoted_shouted}) = $self->unpack('C', 1);		
	$squad->{last_action_timer} = $self->unpack_ctime();
	($squad->{squad_attack_power}) = $self->unpack('v', 2);	
	my ($flag) = $self->unpack('C', 1);		
	if ($flag == 1) {
		($squad->{class}) = $self->unpack('C', 1);	
		if ($squad->{class} == 1) {
			#sim_attack_point
			($squad->{dest_smrt_id}) = $self->unpack('v', 2);	
			$self->set_save_marker($container, 'load', 0, 'sim_attack_point');
			($squad->{major},
			$squad->{target_power_value}) = $self->unpack('Cv', 3);	
			$self->set_save_marker($container, 'load', 1, 'sim_attack_point');
		} else {
			#sim_stay_point
			$self->set_save_marker($container, 'load', 0, 'sim_stay_point');
			($squad->{stay_defended},
			$squad->{next_point_id}) = $self->unpack('Cv', 3);	
			$squad->{begin_time} = $self->_unpack_complex_time();
			$self->set_save_marker($container, 'load', 1, 'sim_stay_point');
		}
	}
	($squad->{items_spawned}) = $self->unpack('C', 1);
	$squad->{bring_item_inited_time} = $self->unpack_ctime();
	$squad->{recover_item_inited_time} = $self->unpack_ctime();
	$self->set_save_marker($container, 'load', 1, 'sim_squad_generic');			
}
sub _unpack_times {
	my ($self, $container, $p) = @_;
	my ($count) = $self->unpack('C', 1);
	while($count--) {
		my $time = $self->_unpack_complex_time();
		push @{$container->{$p->{name}}}, $time;
	}
}
sub _unpack_inited_find_upgrade_tasks {
	my ($self, $container, $p) = @_;
	my ($count) = $self->unpack('v', 2);
	while($count--) {
		my $task = {};
		($task->{k}) = $self->unpack('v', 2);
		my ($num) = $self->unpack('v', 2);
		while($num--) {
			my $subtask = {};
			($subtask->{kk},
			$subtask->{entity_id}) = $self->unpack('Z*v');
			push @{$task->{subtasks}}, $subtask;
		}
		push @{$container->{$p->{name}}}, $task;
	}
}
sub _unpack_rewards {
	my ($self, $container, $p) = @_;
	my ($count) = $self->unpack('C', 1);
	while($count--) {
		my $comm = {};
		($comm->{community}) = $self->unpack('Z*');
		my ($num) = $self->unpack('C', 1);
		while($num--) {
			my $reward = {};
			($reward->{is_money}) = $self->unpack('C', 1);
			if ($reward->{is_money} == 1) {
				($reward->{amount}) = $self->unpack('v', 2);
			} else {
				($reward->{item_name}) = $self->unpack('Z*');
			}
			push @{$comm->{rewards}}, $reward;
		}
		push @{$container->{$p->{name}}}, $comm;
	}
}
sub _unpack_CGeneralTask {
	my ($self, $task, $container) = @_;
	$self->set_save_marker($container, 'load', 0, 'CGeneralTask');
	($task->{entity_id},
	$task->{prior},
	$task->{status},
	$task->{actor_helped},
	$task->{community},
	$task->{actor_come},
	$task->{actor_ignore}) = $self->unpack('vCCCZ*CC');
	$task->{inited_time} = $self->unpack_ctime();
	$self->set_save_marker($container, 'load', 1, 'CGeneralTask');
}
sub _unpack_CStorylineTask {
	my ($self, $task, $container) = @_;
	$self->set_save_marker($container, 'load', 0, 'CStorylineTask');
	$self->_unpack_CGeneralTask($task, $container);
	($task->{target}) = $self->unpack('V', 4);
	$self->set_save_marker($container, 'load', 1, 'CStorylineTask');
}
sub _unpack_CEliminateSmartTask {
	my ($self, $task, $container) = @_;
	$self->set_save_marker($container, 'load', 0, 'CEliminateSmartTask');
	$self->_unpack_CGeneralTask($task, $container);
	($task->{target},
	$task->{src_obj},
	$task->{faction}) = $self->unpack('vZ*Z*');
	$self->set_save_marker($container, 'load', 1, 'CEliminateSmartTask');
}
sub _unpack_CCaptureSmartTask {
	my ($self, $task, $container) = @_;
	$self->set_save_marker($container, 'load', 0, 'CCaptureSmartTask');
	$self->_unpack_CGeneralTask($task, $container);
	($task->{target},
	$task->{state},
	$task->{counter_attack_community},
	$task->{counter_squad},
	$task->{src_obj},
	$task->{faction}) = $self->unpack('vZ*Z*Z*Z*Z*');
	$self->set_save_marker($container, 'load', 1, 'CCaptureSmartTask');
}
sub _unpack_CDefendSmartTask {
	my ($self, $task, $container) = @_;
	$self->set_save_marker($container, 'load', 0, 'CDefendSmartTask');
	$self->_unpack_CGeneralTask($task, $container);
	($task->{target}) = $self->unpack('v');
	$task->{last_called_time} = $self->unpack_ctime();
	$self->set_save_marker($container, 'load', 1, 'CDefendSmartTask');
}
sub _unpack_CBringItemTask {
	my ($self, $task, $container) = @_;
	$self->set_save_marker($container, 'load', 0, 'CBringItemTask');
	$self->_unpack_CGeneralTask($task, $container);
	($task->{state},
	$task->{ri_counter},
	$task->{target},
	$task->{squad_id}) = $self->unpack('Z*CvZ*');
	my ($num) = $self->unpack('C', 1);
	while ($num--) {
		my $requested_item = {};
		($requested_item->{id}) = $self->unpack('Z*');
		@{$requested_item->{items}} = $self->unpack('v/C');
		push @{$task->{requested_items}}, $requested_item;
	}
	$self->set_save_marker($container, 'load', 1, 'CBringItemTask');
}
sub _unpack_CRecoverItemTask {
	my ($self, $task, $container) = @_;
	$self->set_save_marker($container, 'load', 0, 'CRecoverItemTask');
	$self->_unpack_CGeneralTask($task, $container);
	($task->{state},
	$task->{squad_id},
	$task->{target_obj_id},
	$task->{presence_requested_item},
	$task->{requested_item}) = $self->unpack('CZ*vCZ*');
	$self->set_save_marker($container, 'load', 1, 'CRecoverItemTask');
}
sub _unpack_CFindUpgradeTask {
	my ($self, $task, $container) = @_;
	$self->set_save_marker($container, 'load', 0, 'CFindUpgradeTask');
	$self->_unpack_CGeneralTask($task, $container);
	($task->{state},
	$task->{presence_requested_item},
	$task->{requested_item}) = $self->unpack('Z*CZ*');
	$self->set_save_marker($container, 'load', 1, 'CFindUpgradeTask');
}
sub _unpack_CHideFromSurgeTask {
	my ($self, $task, $container) = @_;
	$self->set_save_marker($container, 'load', 0, 'CHideFromSurgeTask');
	$self->_unpack_CGeneralTask($task, $container);
	($task->{target},
	$task->{wait_time},
	$task->{effector_started_time}) = $self->unpack('vvv', 12);
	$self->set_save_marker($container, 'load', 1, 'CHideFromSurgeTask');
}
sub _unpack_CEliminateSquadTask {
	my ($self, $task, $container) = @_;
	$self->set_save_marker($container, 'load', 0, 'CEliminateSquadTask');
	$self->_unpack_CGeneralTask($task, $container);
	($task->{target},
	$task->{src_obj}) = $self->unpack('vZ*');
	$self->set_save_marker($container, 'load', 1, 'CEliminateSquadTask');
}
sub _unpack_inited_tasks {
	my ($self, $container, $p) = @_;
	my ($count) = $self->unpack('v', 2);
	while($count--) {
		my $task = {};
		($task->{base_id},
		$task->{id},
		$task->{type}) = $self->unpack('Z*Z*v');
		SWITCH: {
			($task->{type} == 0 || $task->{type} == 5) && do {$self->_unpack_CStorylineTask($task, $container);last SWITCH;};
			$task->{type} == 1 && do {$self->_unpack_CEliminateSmartTask($task, $container);last SWITCH;};
			$task->{type} == 2 && do {$self->_unpack_CCaptureSmartTask($task, $container);last SWITCH;};
			($task->{type} == 3 || $task->{type} == 4) && do {$self->_unpack_CDefendSmartTask($task, $container);last SWITCH;};
			$task->{type} == 6 && do {$self->_unpack_CBringItemTask($task, $container);last SWITCH;};
			$task->{type} == 7 && do {$self->_unpack_CRecoverItemTask($task, $container);last SWITCH;};
			$task->{type} == 8 && do {$self->_unpack_CFindUpgradeTask($task, $container);last SWITCH;};
			$task->{type} == 9 && do {$self->_unpack_CHideFromSurgeTask($task, $container);last SWITCH;};
			$task->{type} == 10 && do {$self->_unpack_CEliminateSquadTask($task, $container);last SWITCH;};
		}
		push @{$container->{$p->{name}}}, $task;
	}
}
sub _unpack_minigames {
	my ($self, $container, $p) = @_;
	my ($count) = $self->unpack('v', 2);
	while($count--) {
		my $minigame = {};
		($minigame->{key},
		$minigame->{profile},
		$minigame->{state}) = $self->unpack('Z*Z*Z*');
		if ($minigame->{profile} eq 'CMGCrowKiller') {
			$self->set_save_marker($container, 'load', 0, 'CMGCrowKiller');
			($minigame->{param_highscore},
			$minigame->{param_timer},
			$minigame->{param_win}) = $self->unpack('CvC', 4);
			@{$minigame->{param_crows_to_kill}} = $self->unpack('C/C');
			($minigame->{param_money_multiplier},
			$minigame->{param_champion_multiplier},
			$minigame->{param_selected},
			$minigame->{param_game_type},
			$minigame->{high_score},
			$minigame->{timer},
			$minigame->{time_out},
			$minigame->{killed_counter},
			$minigame->{win}) = $self->unpack('vvCZ*CvvCC');
			$self->set_save_marker($container, 'load', 1, 'CMGCrowKiller');
		} elsif ($minigame->{profile} eq 'CMGShooting') {
			$self->set_save_marker($container, 'load', 0, 'CMGShooting');
			($minigame->{param_game_type},
			$minigame->{param_wpn_type},
			$minigame->{param_stand_way},
			$minigame->{param_look_way},
			$minigame->{param_stand_way_back},
			$minigame->{param_look_way_back},
			$minigame->{param_obj_name}) = $self->unpack('Z*Z*Z*Z*Z*Z*Z*');
			($minigame->{param_is_u16}) = $self->unpack('C', 1);
			if ($minigame->{param_is_u16} == 0) {
				($minigame->{param_win}) = $self->unpack('C', 1);
			} else {
				($minigame->{param_win}) = $self->unpack('v', 2);
			}
			($minigame->{param_distance},
			$minigame->{param_ammo}) = $self->unpack('CC', 2);
			my ($count) = $self->unpack('C', 1);
			while($count--) {
				my @target = $self->unpack('C/(Z*)');
				push @{$minigame->{targets}}, \@target;
			}
			($minigame->{param_target_counter}) = $self->unpack('C', 1);
			@{$minigame->{inventory_items}} = $self->unpack('C/v');
			($minigame->{prev_time},
			$minigame->{type}) = $self->unpack('VZ*');
			if ($minigame->{type} eq 'training' ||
				$minigame->{type} eq 'points') {
				$self->set_save_marker($container, 'load', 0, $minigame->{type});
				($minigame->{win},
				$minigame->{ammo},
				$minigame->{cur_target},
				$minigame->{points},
				$minigame->{ammo_counter}) = $self->unpack('vvZ*vC');
				$self->set_save_marker($container, 'load', 1, $minigame->{type});
			} elsif ($minigame->{type} eq 'count') {
				$self->set_save_marker($container, 'load', 0, $minigame->{type});
				($minigame->{wpn_type},
				$minigame->{win},
				$minigame->{ammo}) = $self->unpack('Z*CC');
				my ($count) = $self->unpack('C', 1);
				while($count--) {
					my @target = $self->unpack('C/(Z*)');
					push @{$minigame->{targets}}, \@target;
				}
				($minigame->{distance},
				$minigame->{cur_target},
				$minigame->{points},
				$minigame->{scored},
				$minigame->{ammo_counter}) = $self->unpack('CZ*CCC');
				$self->set_save_marker($container, 'load', 1, $minigame->{type});
			} elsif ($minigame->{type} eq 'three_hit_training') {
				$self->set_save_marker($container, 'load', 0, $minigame->{type});
				($minigame->{wpn_type},
				$minigame->{win},
				$minigame->{ammo}) = $self->unpack('Z*vC');
				my ($count) = $self->unpack('C', 1);
				while($count--) {
					my @target = $self->unpack('C/(Z*)');
					push @{$minigame->{targets}}, \@target;
				}
				($minigame->{distance},
				$minigame->{cur_target},
				$minigame->{points},
				$minigame->{scored},
				$minigame->{ammo_counter},
				$minigame->{target_counter},
				$minigame->{target_hit}) = $self->unpack('CZ*vCCCC');
				$self->set_save_marker($container, 'load', 1, $minigame->{type});
			} elsif ($minigame->{type} eq 'all_targets') {
				$self->set_save_marker($container, 'load', 0, $minigame->{type});
				($minigame->{wpn_type},
				$minigame->{win},
				$minigame->{ammo}) = $self->unpack('Z*vC');
				my ($count) = $self->unpack('C', 1);
				while($count--) {
					push @{$minigame->{targets}}, \$self->unpack('C/(Z*)');
					push @{$minigame->{hitted_targets}}, \$self->unpack('C/(CZ*)');
				}
				($minigame->{ammo_counter},
				$minigame->{time},
				$minigame->{target_counter},
				$minigame->{prev_time},
				$minigame->{more_targets},
				$minigame->{last_target}) = $self->unpack('CvCVCZ*');
				$self->set_save_marker($container, 'load', 1, $minigame->{type});
			} elsif ($minigame->{type} eq 'count_on_time') {
				$self->set_save_marker($container, 'load', 0, $minigame->{type});
				($minigame->{wpn_type},
				$minigame->{win},
				$minigame->{ammo}) = $self->unpack('Z*CC');
				my ($count) = $self->unpack('C', 1);
				while($count--) {
					push @{$minigame->{targets}}, \$self->unpack('C/(Z*)');
				}
				($minigame->{distance},
				$minigame->{cur_target},
				$minigame->{points},
				$minigame->{scored},
				$minigame->{ammo_counter},
				$minigame->{time},
				$minigame->{prev_time}) = $self->unpack('CZ*CCCCV');				
				$self->set_save_marker($container, 'load', 1, $minigame->{type});
			} elsif ($minigame->{type} eq 'ten_targets') {
				$self->set_save_marker($container, 'load', 0, $minigame->{type});
				($minigame->{wpn_type},
				$minigame->{win},
				$minigame->{ammo}) = $self->unpack('Z*CC');
				my ($count) = $self->unpack('C', 1);
				while($count--) {
					push @{$minigame->{targets}}, \$self->unpack('C/(Z*)');
				}
				($minigame->{distance},
				$minigame->{cur_target},
				$minigame->{points},
				$minigame->{scored},
				$minigame->{ammo_counter},
				$minigame->{time},
				$minigame->{prev_time}) = $self->unpack('CZ*CCCvV');				
				$self->set_save_marker($container, 'load', 1, $minigame->{type});
			} elsif ($minigame->{type} eq 'two_seconds_standing') {
				$self->set_save_marker($container, 'load', 0, $minigame->{type});
				($minigame->{wpn_type},
				$minigame->{win},
				$minigame->{ammo}) = $self->unpack('Z*CC');
				my ($count) = $self->unpack('C', 1);
				while($count--) {
					push @{$minigame->{targets}}, \$self->unpack('C/(Z*)');
				}
				($minigame->{distance},
				$minigame->{cur_target},
				$minigame->{points},
				$minigame->{ammo_counter},
				$minigame->{time},
				$minigame->{prev_time}) = $self->unpack('CZ*CCCV');				
				$self->set_save_marker($container, 'load', 1, $minigame->{type});
			}
			$self->set_save_marker($container, 'load', 1, 'CMGShooting');	
		}
		push @{$container->{$p->{name}}}, $minigame;
	}
}
#pack
sub pack {
	my $self = shift;
	my $template = shift;
fail("template is not defined") if !(defined $template);
fail("data is not defined") if !scalar( @_ );
fail("packet is not defined") unless defined $self;
#	print "@_\n";
	$self->{data} .= CORE::pack($template, @_);
}
sub pack_properties {
	my $self = shift;
	my $container = shift;

	foreach my $p (@_) {
#print "$p->{name} = ";
		my $template = template_for_scalar->{$p->{type}};
		defined $template				&& do {$self->_pack_scalar($template, $container, $p); next;};
		($p->{type} eq 'u24')			&& do {$self->_pack_u24($container, $p); next;};
		($p->{type} =~ /^l/)			&& do {$self->_pack_complex($container, $p); next;};
		($p->{type} eq 'shape')			&& do {$self->_pack_shape($container, $p); next;};
		($p->{type} eq 'skeleton')		&& do {$self->_pack_skeleton($container, $p); next;};
		($p->{type} eq 'supplies')		&& do {$self->_pack_supplies($container, $p); next;};
		($p->{type} =~ /afspawns/)		&& do {$self->_pack_artefact_spawns($container, $p); next;};
		($p->{type} eq 'ordaf')			&& do {$self->_pack_ordered_artefacts($container, $p); next;};
		($p->{type} eq 'CTime')			&& do {$self->_pack_ctime($container->{$p->{name}}); next;};
		($p->{type} eq 'complex_time')	&& do {$self->_pack_complex_time($container->{$p->{name}}); next;};
		($p->{type} eq 'npc_info')		&& do {$self->_pack_npc_info($container, $p); next;};
		($p->{type} eq 'sdir')			&& do {$self->_pack_sdir($container, $p); next;};
		#SOC
		($p->{type} eq 'jobs')			&& do {$self->_pack_jobs($container, $p); next;};
		#CS
		($p->{type} eq 'covers')		&& do {$self->_pack_covers($container, $p); next;};
		($p->{type} eq 'squads')		&& do {$self->_pack_squads($container, $p); next;};
		($p->{type} eq 'sim_squads')	&& do {$self->_pack_sim_squads($container, $p); next;};
		($p->{type} eq 'inited_tasks')		&& do {$self->_pack_inited_tasks($container, $p); next;};
		($p->{type} eq 'inited_find_upgrade_tasks')		&& do {$self->_pack_inited_find_upgrade_tasks($container, $p); next;};
		($p->{type} eq 'rewards')		&& do {$self->_pack_rewards($container, $p); next;};
		($p->{type} eq 'minigames')		&& do {$self->_pack_minigames($container, $p); next;};
		#COP
		($p->{type} eq 'times')			&& do {$self->_pack_times($container, $p); next;};
		$self->_pack_vector($container, $p);
	}
}
sub _pack_scalar {
	my ($self, $template, $container, $p) = @_;
	if ($p->{type} =~ /q(.*)/) {
		my $func = "convert_u".$1;
		$container->{$p->{name}} = sub_hash->{$func}($container->{$p->{name}}, -1, 1);
	}	
	$self->pack($template, $container->{$p->{name}});
}
sub _pack_u24 {
	my ($self, $container, $p) = @_;
	$self->pack('CCC', CORE::unpack('CCCC', CORE::pack('V', $container->{$p->{name}})));
}
sub _pack_complex {
	my ($self, $container, $p) = @_;
	my $n = $#{$container->{$p->{name}}} + 1;
	if ($p->{type} eq 'l8u8v') {
		$self->pack("CC$n", $n, @{$container->{$p->{name}}});
	} elsif ($p->{type} eq 'l8u16v') {
		$self->pack("Cv$n", $n, @{$container->{$p->{name}}});
	} elsif ($p->{type} eq 'l8u32v') {
		$self->pack("CV$n", $n, @{$container->{$p->{name}}});
	} elsif ($p->{type} eq 'l8szv') {
		$self->pack("C(Z*)$n", $n, @{$container->{$p->{name}}});
	} elsif ($p->{type} eq 'l8szbv') {
		$n = $n/2;
		$self->pack("C(Z*C)$n", $n, @{$container->{$p->{name}}});
	} elsif ($p->{type} eq 'l8szu16v') {
		$n = $n/2;
		$self->pack("C(Z*v)$n", $n, @{$container->{$p->{name}}});
	} elsif ($p->{type} eq 'l8u16u8v') {
		$n = $n/2;
		$self->pack("C(v*C)$n", $n, @{$container->{$p->{name}}});
	} elsif ($p->{type} eq 'l8u16u16v') {
		$n = $n/2;
		$self->pack("C(v*v)$n", $n, @{$container->{$p->{name}}});
	} elsif ($p->{type} eq 'l16u16v') {
		$self->pack("vv$n", $n, @{$container->{$p->{name}}});
	} elsif ($p->{type} eq 'l32u8v') {
		$self->pack("VC$n", $n, @{$container->{$p->{name}}});
	} elsif ($p->{type} eq 'l32u16v') {
		$self->pack("Vv$n", $n, @{$container->{$p->{name}}});
	} elsif ($p->{type} eq 'l32u32v') {
		$self->pack("VV$n", $n, @{$container->{$p->{name}}});
	} elsif ($p->{type} eq 'l32szv') {
		$self->pack("V(Z*)$n", $n, @{$container->{$p->{name}}});
	}
}
sub _pack_vector {
	my ($self, $container, $p) = @_;
	if ($p->{type} =~ /q(\d+)/) {
		my $func = "convert_u".$1;
		foreach (@{$container->{$p->{name}}}) {
			$_ = sub_hash->{$func}($_, -1, 1);
		}
	}
	$self->pack(template_for_vector->{$p->{type}}, @{$container->{$p->{name}}});
}
sub _pack_sdir {
	my ($self, $container, $p) = @_;
	my ($x, $y, $z) = @{$container->{$p->{name}}};
	my ($s) = sqrt($x*$x + $y*$y + $z*$z);
	if ($s > 0.0000001) {
		$container->{$p->{name}}[0] /= $s;
		$container->{$p->{name}}[1] /= $s;
		$container->{$p->{name}}[2] /= $s;
		$self->_pack_dir($container, $p);
	} else {
		$s = 0.0;
		$container->{$p->{name}}[0] = 0;
		$container->{$p->{name}}[1] = 0;
		$container->{$p->{name}}[2] = 0;
		$self->pack('v', 0);
	}
	$self->pack('f', $s);
}
sub _pack_dir {
	my ($self, $container, $p) = @_;
	my ($x, $y, $z) = @{$container->{$p->{name}}};
	my ($i, $u, $v);
	my $t = 0;
	if ($x < 0) {
		$t = 0x8000;
		$x = -$x;
	}
	if ($y < 0) {
		$t |= 0x4000;
		$y = -$y;
	}
	if ($z < 0) {
		$t |= 0x2000;
		$z = -$z;
	}	
	$i = ($x + $y + $z)/126;
	$u = round($x / $i);
	$v = round($y / $i);
	if ($u >= 64) {
		$v = 127 - $v;
		$u = 127 - $u;
	}
	$t |= $v;
	$t |= ($u << 7);
	$self->pack('v', $t);
}
sub _pack_shape {
	my ($self, $container, $p) = @_;	
	$self->pack('C', $#{$container->{$p->{name}}} + 1);
	foreach my $shape (@{$container->{$p->{name}}}) {
		$self->pack('C', $$shape{type});
		if ($$shape{type} == 0) {
			$self->pack('f4', @{$$shape{sphere}});
		} elsif ($$shape{type} == 1) {
			$self->pack('f12', @{$$shape{box}});
		}
	}
}
sub _pack_skeleton {
	my ($self, $container, $p) = @_;	
	$self->pack('C8vf3f3v', @{$container->{bones_mask}}, $container->{root_bone}, @{$container->{bbox_min}}, @{$container->{bbox_max}}, $#{$container->{bones}} + 1);
	foreach my $bone (@{$container->{bones}}) {
		my $i = 0;
		foreach (@{$$bone{ph_position}}) {
			$_ = convert_u8($_, $container->{bbox_min}[$i], $container->{bbox_max}[$i]);
			$i++;
		}
		$self->pack('C3', @{$$bone{ph_position}});
		foreach (@{$$bone{ph_rotation}}) {
			$_ = convert_u8($_, -1, 1);
		}
		$self->pack('C4', @{$$bone{ph_rotation}});
		$self->pack('C', $$bone{enabled});
	}
}
sub _pack_supplies {
	my ($self, $container, $p) = @_;
	$self->pack('V', $#{$container->{$p->{name}}} + 1);
	foreach my $sect (@{$container->{$p->{name}}}) {
		$self->pack('Z*Vff', $$sect{section_name}, $$sect{item_count}, $$sect{min_factor}, $$sect{max_factor});
	}
}
sub _pack_artefact_spawns {
	my ($self, $container, $p) = @_;
	$self->pack('v', $#{$container->{$p->{name}}} + 1);
	if ($p->{type} eq 'afspawns') {
		foreach my $sect (@{$container->{$p->{name}}}) {
			$self->pack('Z*f', $$sect{section_name}, $$sect{weight});
		}
	} else {
		foreach my $sect (@{$container->{$p->{name}}}) {
			$self->pack('Z*V', $$sect{section_name}, $$sect{weight});
		}	
	}
}
sub _pack_ordered_artefacts {
	my ($self, $container, $p) = @_;
	$self->pack('V', $#{$container->{$p->{name}}} + 1);
	foreach my $sect (@{$container->{$p->{name}}}) {
		$self->pack('Z*VV', $$sect{unknown_string}, $$sect{unknown_number}, $#{$sect->{af_sects}} + 1);
		foreach my $obj (@{$sect->{af_sects}}) {
			$self->pack('Z*VV', $$obj{artefact_name}, $$obj{number_1}, $$obj{number_2});
		}
	}
}
sub _pack_ctime {
	my ($self, $time) = @_;
	my @date;
	if ($time != 0) {
		@date = $time->get_all();
	} else {
		$date[0] = 2000;
	}
	$date[0] -= 2000;
	if ($date[0] == 0 || $date[0] == 255) {
		$self->pack('C', $date[0]);
	} else {
		$self->pack('C6v', @date);
	}
}
sub _pack_complex_time {
	my ($self, $time) = @_;
	my $flag = 0;
	$flag = 1 if $time != 0;
	$self->pack('C', $flag);
	$self->_pack_ctime($time) if $flag == 1;
}
sub _pack_jobs {
	my ($self, $container, $p) = @_;
	$self->pack('C', $#{$container->{$p->{name}}} + 1);
	foreach my $job (@{$container->{$p->{name}}}) {
		$self->pack('VVV', $job->{job_begin}, $job->{job_fill_idle}, $job->{job_idle_after_death_end});
	}
}
sub	_pack_npc_info {
	my $self = shift;
	if ($_[0]->{version} >= 122) {
		$self->_pack_npc_info_cop(@_);
	} elsif ($_[0]->{version} >= 117) {
		$self->_pack_npc_info_soc(@_);
	} else {
		$self->_pack_npc_info_old(@_);
	}
}
sub _pack_npc_info_old {
	my ($self, $container, $p) = @_;
	$self->pack('C', $#{$container->{$p->{name}}} + 1);
	foreach my $info (@{$container->{$p->{name}}}) {
		$self->pack('vCCCC', $info->{o_id}, $info->{group}, $info->{squad}, $info->{move_offline}, $info->{switch_offline});
		$self->_pack_ctime($info->{stay_end});
		$self->pack('C', $info->{jobN}) if $container->{script_version} >= 1 && $container->{gulagN} != 0;
	}
}
sub _pack_npc_info_soc {
	my ($self, $container, $p) = @_;
	$self->pack('C', $#{$container->{$p->{name}}} + 1);
	foreach my $info (@{$container->{$p->{name}}}) {
		$self->pack('vCCC', $info->{o_id}, $info->{o_group}, $info->{o_squad}, $info->{exclusive});
		$self->_pack_ctime($info->{stay_end});
		$self->pack('C', $info->{Object_begin_job});
		$self->pack('C', $info->{Object_didnt_begin_job}) if $container->{script_version} > 4;
		$self->pack('C', $info->{jobN});
	}
}
sub _pack_npc_info_cop {
	my ($self, $container, $p) = @_;
	$self->pack('C', $#{$container->{$p->{name}}} + 1);
	foreach my $info (@{$container->{$p->{name}}}) {
		$self->pack('vCCCZ*', $info->{id}, $info->{job_prior}, $info->{job_id}, $info->{begin_job}, $info->{need_job});
	}
}
sub _pack_covers {
	my ($self, $container, $p) = @_;
	$self->pack('C', $#{$container->{$p->{name}}} + 1);
	foreach my $cover (@{$container->{$p->{name}}}) {
		$self->pack('vVf3f3C', $cover->{npc_id}, $cover->{cover_vertex_id}, @{$cover->{cover_position}}, @{$cover->{look_pos}}, $cover->{is_smart_cover});
	}
}
sub _pack_squads {
	my ($self, $container, $p) = @_;
	$self->pack('C', $#{$container->{$p->{name}}} + 1);
	foreach my $squad (@{$container->{$p->{name}}}) {
		$self->pack('Z*Z*CCC', $squad->{squad_name}, $squad->{squad_stage}, $squad->{squad_prepare_shouted}, $squad->{squad_attack_shouted}, $squad->{squad_attack_squad});
		$self->_pack_complex_time($squad->{squad_inited_defend_time});
		$self->_pack_complex_time($squad->{squad_start_attack_wait});
		$self->_pack_complex_time($squad->{squad_last_defence_kill_time});
		$self->pack('f', $squad->{squad_power});
	}
}
sub _pack_sim_squads {
	my ($self, $container, $p) = @_;
	$self->pack('v', $#{$container->{$p->{name}}} + 1);
	foreach my $squad (@{$container->{$p->{name}}}) {
		$self->pack('Z*Z*C', $squad->{squad_id}, $squad->{settings_id}, $squad->{is_scripted});
		$self->_pack_sim_squad_generic($container, $squad);
		if ($squad->{is_scripted} == 1) {
			$self->set_save_marker($container, 'save', 0, 'sim_squad_scripted');
			$self->pack('CCCC', $squad->{next_target}, $squad->{need_free_update}, $squad->{relationship}, $squad->{sympathy});
			$self->set_save_marker($container, 'save', 1, 'sim_squad_scripted');
		}
	}
}
sub _pack_sim_squad_generic {
	my ($self, $container, $squad) = @_;
	$self->set_save_marker($container, 'save', 0, 'sim_squad_generic');
	$self->pack('vvvv', $squad->{smart_id}, $squad->{assigned_target_smart_id}, $squad->{sim_combat_id}, $squad->{delayed_attack_task});
	my $n = $#{$squad->{random_tasks}} + 1;
	$n = $n/2;
	$self->pack("C(vv)$n", $n, @{$squad->{random_tasks}});
	$self->pack('Cfv', $squad->{npc_count}, $squad->{squad_power}, $squad->{commander_id});
	$n = $#{$squad->{squad_npc}} + 1;
	$self->pack("C(v)$n", $n, @{$squad->{squad_npc}});	
	$self->pack('C', $squad->{spoted_shouted});	
	$self->_pack_ctime($squad->{last_action_timer});
	$self->pack('v', $squad->{squad_attack_power});	
	if (defined $squad->{class}) {
		$self->pack('C', 1);	
		$self->pack('C', $squad->{class});	
		if ($squad->{class} == 1) {
			#sim_attack_point
			$self->pack('v', $squad->{dest_smrt_id});
			$self->set_save_marker($container, 'save', 0, 'sim_attack_point');
			$self->pack('Cv', $squad->{major}, $squad->{target_power_value});
			$self->set_save_marker($container, 'save', 1, 'sim_attack_point');
		} else {
			$self->set_save_marker($container, 'save', 0, 'sim_stay_point');
			$self->pack('Cv', $squad->{stay_defended}, $squad->{next_point_id});
			$self->_pack_complex_time($squad->{begin_time});
			$self->set_save_marker($container, 'save', 1, 'sim_stay_point');			
		}
	} else {
		$self->pack('C', 0);	
	}
	$self->pack('C', $squad->{items_spawned});	
	$self->_pack_ctime($squad->{bring_item_inited_time});
	$self->_pack_ctime($squad->{recover_item_inited_time});
	$self->set_save_marker($container, 'save', 1, 'sim_squad_generic');
}
sub _pack_times {
	my ($self, $container, $p) = @_;
	$self->pack('C', $#{$container->{$p->{name}}} + 1);
	foreach (@{$container->{$p->{name}}}) {
		$self->_pack_complex_time($_);
	}
}
sub _pack_inited_find_upgrade_tasks {
	my ($self, $container, $p) = @_;
	$self->pack('v', $#{$container->{$p->{name}}} + 1);
	foreach (@{$container->{$p->{name}}}) {
		$self->unpack('vv', $_->{k}, $#{$_->{subtasks}} + 1);
		foreach my $subtask (@{$_->{subtasks}}) {
			$self->unpack('Z*v', $subtask->{kk}, $subtask->{entity_id});
		}
	}
}
sub _pack_rewards {
	my ($self, $container, $p) = @_;
	$self->pack('C', $#{$container->{$p->{name}}} + 1);
	foreach (@{$container->{$p->{name}}}) {
		$self->pack('Z*C', $_->{community}, $#{$_->{rewards}} + 1);
		foreach my $reward (@{$_->{rewards}}) {
			$self->pack('C', $reward->{is_money});
			if ($reward->{is_money} == 1) {
				$self->pack('v', $reward->{amount});
			} else {
				$self->pack('Z*', $reward->{item_name});
			}
		}
	}
}
sub _pack_CGeneralTask {
	my ($self, $task, $container) = @_;
	$self->set_save_marker($container, 'save', 0, 'CGeneralTask');
	$self->pack('vCCCZ*CC', $task->{entity_id}, $task->{prior}, $task->{status}, $task->{actor_helped}, $task->{community}, $task->{actor_come}, $task->{actor_ignore});
	$self->_pack_ctime($task->{inited_time});
	$self->set_save_marker($container, 'save', 1, 'CGeneralTask');
}
sub _pack_CStorylineTask {
	my ($self, $task, $container) = @_;
	$self->set_save_marker($container, 'save', 0, 'CStorylineTask');
	$self->_pack_CGeneralTask($task, $container);
	$self->pack('V', $task->{target});
	$self->set_save_marker($container, 'save', 1, 'CStorylineTask');
}
sub _pack_CEliminateSmartTask {
	my ($self, $task, $container) = @_;
	$self->set_save_marker($container, 'save', 0, 'CEliminateSmartTask');
	$self->_pack_CGeneralTask($task, $container);
	$self->pack('vZ*Z*', $task->{target}, $task->{src_obj}, $task->{faction});
	$self->set_save_marker($container, 'save', 1, 'CEliminateSmartTask');
}
sub _pack_CCaptureSmartTask {
	my ($self, $task, $container) = @_;
	$self->set_save_marker($container, 'save', 0, 'CCaptureSmartTask');
	$self->_pack_CGeneralTask($task, $container);
	$self->pack('vZ*Z*Z*Z*Z*', $task->{target}, $task->{state}, $task->{counter_attack_community}, $task->{counter_squad}, $task->{src_obj}, $task->{faction});
	$self->set_save_marker($container, 'save', 1, 'CCaptureSmartTask');
}
sub _pack_CDefendSmartTask {
	my ($self, $task, $container) = @_;
	$self->set_save_marker($container, 'save', 0, 'CDefendSmartTask');
	$self->_pack_CGeneralTask($task, $container);
	$self->pack('v', $task->{target});
	$self->pack_ctime($task->{last_called_time});
	$self->set_save_marker($container, 'save', 1, 'CDefendSmartTask');
}
sub _pack_CBringItemTask {
	my ($self, $task, $container) = @_;
	$self->set_save_marker($container, 'save', 0, 'CBringItemTask');
	$self->_pack_CGeneralTask($task, $container);
	$self->pack('Z*CvZ*C', $task->{state}, $task->{ri_counter}, $task->{target}, $task->{squad_id}, $#{$task->{requested_items}} + 1);
	foreach (@{$task->{requested_items}}) {
		$self->pack('Z*', $_->{id});
		my $n = $#{$_->{items}} + 1;
		$self->pack("v(C)$n", @{$_->{items}});
	}
	$self->set_save_marker($container, 'save', 1, 'CBringItemTask');
}
sub _pack_CRecoverItemTask {
	my ($self, $task, $container) = @_;
	$self->set_save_marker($container, 'save', 0, 'CRecoverItemTask');
	$self->_pack_CGeneralTask($task, $container);
	$self->pack('CZ*vCZ*', $task->{state}, $task->{squad_id}, $task->{target_obj_id}, $task->{presence_requested_item}, $task->{requested_item});
	$self->set_save_marker($container, 'save', 1, 'CRecoverItemTask');
}
sub _pack_CFindUpgradeTask {
	my ($self, $task, $container) = @_;
	$self->set_save_marker($container, 'save', 0, 'CFindUpgradeTask');
	$self->_pack_CGeneralTask($task, $container);
	$self->pack('Z*CZ*', $task->{state}, $task->{presence_requested_item}, $task->{requested_item});
	$self->set_save_marker($container, 'save', 1, 'CFindUpgradeTask');
}
sub _pack_CHideFromSurgeTask {
	my ($self, $task, $container) = @_;
	$self->set_save_marker($container, 'save', 0, 'CHideFromSurgeTask');
	$self->_pack_CGeneralTask($task, $container);
	$self->pack('vvv', $task->{target}, $task->{wait_time}, $task->{effector_started_time});
	$self->set_save_marker($container, 'save', 1, 'CHideFromSurgeTask');
}
sub _pack_CEliminateSquadTask {
	my ($self, $task, $container) = @_;
	$self->set_save_marker($container, 'save', 0, 'CEliminateSquadTask');
	$self->_pack_CGeneralTask($task, $container);
	$self->pack('vZ*', $task->{target}, $task->{src_obj});
	$self->set_save_marker($container, 'save', 1, 'CEliminateSquadTask');
}
sub _pack_inited_tasks {
	my ($self, $container, $p) = @_;
	my ($count) = $self->pack('v', $#{$container->{$p->{name}}} + 1);
	foreach (@{$container->{$p->{name}}}) {
		$self->pack('Z*Z*v', $_->{base_id}, $_->{id}, $_->{type});
		SWITCH: {
			($_->{type} == 0 || $_->{type} == 5) && do {$self->_pack_CStorylineTask($_, $container);last SWITCH;};
			$_->{type} == 1 && do {$self->_pack_CEliminateSmartTask($_, $container);last SWITCH;};
			$_->{type} == 2 && do {$self->_pack_CCaptureSmartTask($_, $container);last SWITCH;};
			($_->{type} == 3 || $_->{type} == 4) && do {$self->_pack_CDefendSmartTask($_, $container);last SWITCH;};
			$_->{type} == 6 && do {$self->_pack_CBringItemTask($_, $container);last SWITCH;};
			$_->{type} == 7 && do {$self->_pack_CRecoverItemTask($_, $container);last SWITCH;};
			$_->{type} == 8 && do {$self->_pack_CFindUpgradeTask($_, $container);last SWITCH;};
			$_->{type} == 9 && do {$self->_pack_CHideFromSurgeTask($_, $container);last SWITCH;};
			$_->{type} == 10 && do {$self->_pack_CEliminateSquadTask($_, $container);last SWITCH;};
		}
	}
}
sub _pack_minigames {
	my ($self, $container, $p) = @_;
	$self->pack('v', $#{$container->{$p->{name}}} + 1);
	foreach (@{$container->{$p->{name}}}) {
		$self->pack('Z*Z*Z*', $_->{key}, $_->{profile}, $_->{state});
		if ($_->{profile} eq 'CMGCrowKiller') {
			$self->set_save_marker($container, 'save', 0, 'CMGCrowKiller');
			$self->pack('CvC', $_->{param_highscore}, $_->{param_timer}, $_->{param_win});
			my $n = $#{$_->{param_crows_to_kill}} + 1;
			$self->pack("C(C)$n", $n, @{$_->{param_crows_to_kill}});
			$self->pack('vvCZ*CvvCC', $_->{param_money_multiplier}, $_->{param_champion_multiplier}, $_->{param_selected}, $_->{param_game_type}, $_->{high_score}, $_->{timer}, $_->{time_out}, $_->{killed_counter}, $_->{win});
			$self->set_save_marker($container, 'save', 1, 'CMGCrowKiller');
		} elsif ($_->{profile} eq 'CMGShooting') {
			$self->set_save_marker($container, 'save', 0, 'CMGShooting');
			$self->pack('Z*Z*Z*Z*Z*Z*Z*', $_->{param_game_type}, $_->{param_wpn_type}, $_->{param_stand_way}, $_->{param_look_way}, $_->{param_stand_way_back}, $_->{param_look_way_back}, $_->{param_obj_name});
			$self->pack('C', $_->{param_is_u16});
			if ($_->{param_is_u16} == 0) {
				$self->pack('C', $_->{param_win});
			} else {
				$self->pack('v', $_->{param_win});
			}
			$self->pack('CCC', $_->{param_distance}, $_->{param_ammo}, $#{$_->{targets}} + 1);
			foreach my $target (@{$_->{targets}}) {
				my $n = $#{$target} + 1;
				$self->pack("C(Z*)$n", $n, @$target);
			}
			$self->pack('C', $_->{param_target_counter});
			my $n = $#{$_->{inventory_items}} + 1;
			$self->pack("C(v)$n", $n, @{$_->{inventory_items}});
			$self->pack('VZ*', $_->{prev_time}, $_->{type});
			if ($_->{type} eq 'training' || $_->{type} eq 'points') {
				$self->set_save_marker($container, 'save', 0, $_->{type});
				$self->pack('vvZ*vC', $_->{win}, $_->{ammo}, $_->{cur_target}, $_->{points}, $_->{ammo_counter});
				$self->set_save_marker($container, 'save', 1, $_->{type});
			} elsif ($_->{type} eq 'count') {
				$self->set_save_marker($container, 'save', 0, $_->{type});
				$self->pack('Z*CCC', $_->{wpn_type}, $_->{win}, $_->{ammo}, $#{$_->{targets}} + 1);
				foreach my $target (@{$_->{targets}}) {
					my $n = $#{$target} + 1;
					$self->pack("C(Z*)$n", $n, @$target);
				}
				$self->pack('CZ*CCC', $_->{distance}, $_->{cur_target}, $_->{points}, $_->{scored}, $_->{ammo_counter});
				$self->set_save_marker($container, 'save', 1, $_->{type});
			} elsif ($_->{type} eq 'three_hit_training') {
				$self->set_save_marker($container, 'save', 0, $_->{type});
				$self->pack('Z*vCC', $_->{wpn_type}, $_->{win}, $_->{ammo}, $#{$_->{targets}} + 1);
				foreach my $target (@{$_->{targets}}) {
					my $n = $#{$target} + 1;
					$self->pack("C(Z*)$n", $n, @$target);
				}
				$self->pack('CZ*vCCCC', $_->{distance}, $_->{cur_target}, $_->{points}, $_->{scored}, $_->{ammo_counter}, $_->{target_counter}, $_->{target_hit});
				$self->set_save_marker($container, 'save', 1, $_->{type});
			} elsif ($_->{type} eq 'all_targets') {
				$self->set_save_marker($container, 'save', 0, $_->{type});
				$self->pack('Z*vCC', $_->{wpn_type}, $_->{win}, $_->{ammo}, $#{$_->{targets}} + 1);
				foreach my $target (@{$_->{targets}}) {
					my $n = $#{$target} + 1;
					$self->pack("C(Z*)$n", $n, @$target);
				}
				foreach my $hitted_target (@{$_->{hitted_targets}}) {
					my $n = $#{$hitted_target} + 1;
					$self->pack("C(Z*)$n", $n, @$hitted_target);
				}
				$self->pack('CvCVCZ*', $_->{ammo_counter}, $_->{time}, $_->{target_counter}, $_->{prev_time}, $_->{more_targets}, $_->{last_target});
				$self->set_save_marker($container, 'save', 1, $_->{type});
			} elsif ($_->{type} eq 'count_on_time') {
				$self->set_save_marker($container, 'save', 0, $_->{type});
				$self->pack('Z*vCC', $_->{wpn_type}, $_->{win}, $_->{ammo}, $#{$_->{targets}} + 1);
				foreach my $target (@{$_->{targets}}) {
					my $n = $#{$target} + 1;
					$self->pack("C(Z*)$n", $n, @$target);
				}
				$self->pack('CZ*CCCCV', $_->{distance}, $_->{cur_target}, $_->{points}, $_->{scored}, $_->{ammo_counter}, $_->{time}, $_->{prev_time});
				$self->set_save_marker($container, 'save', 1, $_->{type});
			} elsif ($_->{type} eq 'ten_targets') {
				$self->set_save_marker($container, 'save', 0, $_->{type});
				$self->pack('Z*vCC', $_->{wpn_type}, $_->{win}, $_->{ammo}, $#{$_->{targets}} + 1);
				foreach my $target (@{$_->{targets}}) {
					my $n = $#{$target} + 1;
					$self->pack("C(Z*)$n", $n, @$target);
				}
				$self->pack('CZ*CCCvV', $_->{distance}, $_->{cur_target}, $_->{points}, $_->{scored}, $_->{ammo_counter}, $_->{time}, $_->{prev_time});
				$self->set_save_marker($container, 'save', 1, $_->{type});
			} elsif ($_->{type} eq 'two_seconds_standing') {
				$self->set_save_marker($container, 'save', 0, $_->{type});
				$self->pack('Z*vCC', $_->{wpn_type}, $_->{win}, $_->{ammo}, $#{$_->{targets}} + 1);
				foreach my $target (@{$_->{targets}}) {
					my $n = $#{$target} + 1;
					$self->pack("C(Z*)$n", $n, @$target);
				}
				$self->pack('CZ*CCCV', $_->{distance}, $_->{cur_target}, $_->{points}, $_->{ammo_counter}, $_->{time}, $_->{prev_time});
				$self->set_save_marker($container, 'save', 1, $_->{type});
			}
			$self->set_save_marker($container, 'save', 1, 'CMGShooting');	
		}
	}
}
#various
sub length {return CORE::length($_[0]->{data})}
sub resid {return CORE::length($_[0]->{data}) - $_[0]->{pos}}
sub r_tell {return $_[0]->{init_length} - $_[0]->resid()}
sub w_tell {return CORE::length($_[0]->{data})}
sub raw {
	if ($#_ == 1) {
		my $out = substr($_[0]->{data}, $_[0]->{pos}, $_[1]);
		$_[0]->{pos} += $_[1];
		return $out;
	} elsif ($#_ == 2) {
		substr($_[0]->{data}, $_[0]->{pos}, $_[1], $_[2]);
	}
}
sub data {
	return $_[0]->{data} if $#_ == 0;
	$_[0]->{data} = $_[1];
}
sub pos {
	return $_[0]->{pos} if $#_ == 0;
	$_[0]->{pos} = $_[1];
}
sub isinf {
	if ($_[0] == 9**9**9 || $_[0] == -9**9**9) {
		return 1;
	}
	return 0;
}
sub isnan {
	if (! defined($_[0] <=> 9**9**9)) {
		return 1;
	}
	return 0;
}
sub set_save_marker {
	my $packet = shift;
	my $object = shift;
	my $mode = shift;
	my $check = shift;
	my $name = shift;
	if ($check) {
		die unless defined($object->{markers}{$name});
		if ($mode eq 'save') {
			my $diff = $packet->w_tell() - $object->{markers}{$name};
			die unless $diff > 0;
			$packet->pack('v', $diff);
		} else {
			my $diff = $packet->r_tell() - $object->{markers}{$name};
			die unless $diff > 0;
			my ($diff1) = $packet->unpack('v', 2);
			die unless $diff == $diff1;
		}
	} else {
		if ($mode eq 'save') {
			$object->{markers}{$name} = $packet->w_tell();
		} else {
			$object->{markers}{$name} = $packet->r_tell();
		}
	}
}
sub convert_q8 {
	my ($u, $min, $max) = @_;
	my $q = $u / 255.0 * ($max - $min) + $min;
	return $q;
}
sub convert_u8 {
	my ($q, $min, $max) = @_;
	my $u = ($q - $min) * 255.0 / ($max - $min);
	return $u;
}
sub convert_q16 {
	my ($u) = @_;
	my $q = (($u / 43.69) - 500.0);
	return $q;
}
sub convert_u16 {
	my ($q) = @_;
	my $u = round((($q + 500.0) * 43.69));
	return $u;
}
sub convert_q16_old {
	my ($u) = @_;
	my $q = (($u / 32.77) - 1000.0);
	return $q;
}
sub convert_u16_old {
	my ($q) = @_;
	my $u = round((($q + 1000.0) * 32.77));
	return $u;
}
sub error_handler {
	my $self = shift;
	my ($container, $template) = @_;
	print "handling error with $container->{section_name}, template $template\n";
	SWITCH: {
		# Nar Sol fix
		($template eq 'C') && (ref($container) eq 'se_zone_anom') && $container->{version} == 118 && $container->{script_version} == 6 && do {
			print "unpacking spawn of Narodnaya Solyanka, huh? OK...\n";
			bless $container, 'cse_alife_anomalous_zone';
			$container->{ini}->{sections_hash}{'sections'}{"'$container->{section_name}'"} = 'cse_alife_anomalous_zone' if defined $container->{ini};
			$container->{flags} |= FL_HANDLED;
			last;
		};
		# future fix
		($template eq 'C') && (ref($container) eq 'se_zone_visual') && $container->{version} == 118 && $container->{script_version} == 6 && do {
			print "unpacking spawn of some mod, huh? OK...\n";
			bless $container, 'cse_alife_zone_visual';
			$container->{ini}->{sections_hash}{'sections'}{"'$container->{section_name}'"} = 'cse_alife_zone_visual' if defined $container->{ini};
			$container->{flags} |= FL_HANDLED;
			last;
		};
		($template eq 'f') && (ref($container) eq 'cse_alife_anomalous_zone') && $container->{version} == 118 && $container->{script_version} == 6 && do {
			print "unpacking spawn of some mod, huh? OK...\n";
			bless $container, 'cse_alife_custom_zone';
			$container->{ini}->{sections_hash}{'sections'}{"'$container->{section_name}'"} = 'cse_alife_custom_zone' if defined $container->{ini};
			$container->{flags} |= FL_HANDLED;
			last;
		};
		# builds 25xx fix
		(ref($container) =~ /cse_alife_item_weapon_/) && $container->{version} == 118 && $container->{script_version} == 5 && do {
			if (ref($container) eq 'cse_alife_item_weapon_shotgun') {
				bless $container, 'cse_alife_item_weapon_magazined';
			} else {
				bless $container, 'cse_alife_item_weapon';
			}
			fix_25xx($self, $container);
			last;
		};		
		(ref($container) =~ /stalker|monster|actor/) && $container->{version} == 118 && $container->{script_version} == 5 && do {
			fix_25xx($self, $container);
			last;
		};		
		fail("unhandled exception\n");
	}
}
sub round {
	my $temp = sprintf("%.2f", $_[0]);
	my $int = int($temp);
	if (($temp - $int) > 0.5000) {
		return ceil($temp);
	} else {
		return floor($temp);
	}
}
sub fix_25xx {
	$_[1]->{flags} |= FL_IS_25XX;
	$_[0]->{pos} = 2;
	$_[1]->update_read($_[0]);
	$_[1]->{flags} |= FL_HANDLED;
	$_[0]->{pos} = 42 if ref($_[1]) =~ /stalker|monster/;
	foreach my $section (keys %{$_[1]->{ini}->{sections_hash}{'sections'}}) {
		if ($_[1]->{ini}->{sections_hash}{'sections'}{$section} =~ /cse_alife_item_weapon_magazined/) {
			$_[1]->{ini}->{sections_hash}{'sections'}{$section} = 'cse_alife_item_weapon';
		} elsif ($_[1]->{ini}->{sections_hash}{'sections'}{$section} eq 'cse_alife_item_weapon_shotgun') {
			$_[1]->{ini}->{sections_hash}{'sections'}{$section} = 'cse_alife_item_weapon_magazined';
		}
	}
}
sub is_handled {return (UNIVERSAL::can($_[0], 'is_handled') && $_[0]->is_handled())}
1;