# Module for importing and exporting variables and data structures
# Update history^
#	26/08/2012 - fix for new fail() syntax
#	09/08/2012 - implementing import/export for some clear sky se_actor properties
######################################################
package stkutils::ini_file;
use strict;
use IO::File;
use stkutils::debug qw(fail);
use stkutils::math;
#use Tie::IxHash;
sub new {
	my $class = shift;
	my ($fn, $mode) = @_;

	my $fh = IO::File->new($fn, $mode) or return undef;

	my $self = {};
	$self->{fh} = $fh;
	$self->{sections_list} = [];
	$self->{sections_hash} = ();
	bless($self, $class);

	$mode eq 'w' and return $self;

	my $section;
	my $skip_section = 0;
	while (<$fh>) {
		$_ =~ qr/^\s*;/ and next;
		if (/^\[(.*)\]\s*:*\s*(\w.*)?/) {
			if (defined $2 && !::is_flag_defined($2)) {
				$skip_section = 1;
				next;
			}
			$section = $1;
			fail('duplicate section '.$section.' found while reading '.$fn) if defined $self->{sections_hash}->{$section};
			push @{$self->{sections_list}}, $section;
			my %tmp = ();
#			tie %tmp, "Tie::IxHash";
			$self->{sections_hash}{$section} = \%tmp;
			$skip_section = 0;
			next;
		}
		if (/^\s*([^=]*?)\s*=\s*(.*?)$/) {
			my ($name, $value) = ($1, $2);
			if ($value =~ /^<<(.*)\s*$/) {
				my $terminator = $1;
				$value = '';
				while (<$fh>) {
					chomp;
					last if $_ =~ /^\s*$terminator\s*$/;
					$value .= "\n".$_;
				}
				die unless defined $_;
				substr ($value, 0, 1) = '';
			}
			$skip_section == 1 and next;
			fail('undefined section found while reading '.$fn) unless defined $section;
			if (($name ne 'custom_data') and $value =~ /^(.+)(?=\s*;+?)/) {
				$value = $1;
			}
			$self->{sections_hash}{$section}{$name} = $value;
		}
	}
	return $self;
}
sub close {
	my $self = shift;
	$self->{fh}->close();
	$self->{fh} = undef;
}
use constant format_for_number => {
	h32	=> '%#x',
	h16	=> '%#x',
	h8	=> '%#x',
	u32	=> '%u',
	u16	=> '%u',
	u8	=> '%u',
	q8	=> '%.8g',
	q16	=> '%.8g',
	q16_old	=> '%.8g',
	s32	=> '%d',
	s16	=> '%d',
	s8	=> '%d',
	f32	=> '%.8g',
};
#export functions
sub export_properties {
	my $self = shift;
	my $comment = shift;
	my $container = shift;

#print $container->{name}."\n";	
	my $fh = $self->{fh};
	print $fh "\n; $comment properties\n" if defined $comment;
	foreach my $p (@_) {
#	print "$p->{name}, $p->{type}\n";
		my $format = format_for_number->{$p->{type}};
		defined $format					&& do {_export_scalar($fh, $format, $container, $p); next;};
		($p->{type} eq 'sz')			&& do {_export_string($fh, $container, $p); next;};
		($p->{type} eq 'shape')			&& do {_export_shape($fh, $container, $p); next;};
		($p->{type} eq 'skeleton')		&& do {_export_skeleton($fh, $container, $p); next;};
		($p->{type} eq 'supplies')		&& do {_export_supplies($fh, $container, $p); next;};
		($p->{type} =~ /afspawns/)		&& do {_export_artefact_spawns($fh, $container, $p); next;};
		($p->{type} eq 'ordaf')			&& do {_export_ordered_artefacts($fh, $container, $p); next;};
		($p->{type} eq 'CTime')			&& do {_export_ctime($fh, $p->{name}, $container->{$p->{name}}); next;};
		($p->{type} eq 'complex_time')	&& do {_export_ctime($fh, $p->{name}, $container->{$p->{name}}); next;};
		($p->{type} eq 'npc_info')		&& do {_export_npc_info($fh, $container, $p); next;};
		#SOC
		($p->{type} eq 'jobs')			&& do {_export_jobs($fh, $container, $p); next;};
		#CS
		($p->{type} eq 'covers')		&& do {_export_covers($fh, $container, $p); next;};
		($p->{type} eq 'squads')		&& do {_export_squads($fh, $container, $p); next;};
		($p->{type} eq 'sim_squads')	&& do {_export_sim_squads($fh, $container, $p); next;};
		($p->{type} eq 'inited_tasks')		&& do {_export_inited_tasks($fh, $container, $p); next;};
		($p->{type} eq 'inited_find_upgrade_tasks')		&& do {_export_inited_find_upgrade_tasks($fh, $container, $p); next;};
		($p->{type} eq 'rewards')		&& do {_export_rewards($fh, $container, $p); next;};
		($p->{type} eq 'minigames')		&& do {_export_minigames($fh, $container, $p); next;};
		#COP
		($p->{type} eq 'times')			&& do {_export_times($fh, $container, $p); next;};
		_export_vector($fh, $container, $p);
	}
}
sub _export_scalar {
	my ($fh, $format, $container, $p) = @_;
	fail('undefined field '.$p->{name}.' for entity '.$container->{name}) unless defined $container->{$p->{name}};
	return if defined($p->{default}) && $container->{$p->{name}} == $p->{default};
	return if defined($p->{default}) && abs($container->{$p->{name}} - $p->{default}) < 0.001 && ($p->{type} eq 'f32' or $p->{type} eq 'q8');
	printf $fh "$p->{name} = $format\n", $container->{$p->{name}};
}
sub _export_string {
	my ($fh, $container, $p) = @_;
	return if defined($p->{default}) && $container->{$p->{name}} eq $p->{default};
	my $value = $container->{$p->{name}};
	if ($value =~ /\n/) {
		print $fh "$p->{name} = <<END\n$value\nEND\n";
	} else {
		print $fh "$p->{name} = $value\n";
	}
}
sub _export_vector {
	my ($fh, $container, $p) = @_;
	if ($p->{type} =~ /dumb/) {
		printf $fh "$p->{name} = ".unpack('H*', $container->{$p->{name}})."\n";	
	} else {
		return if ( $p->{ default } && @{ $p->{ default } } && comp_arrays( $container, $p ) );
		print $fh "$p->{name} = ", join(', ', @{$container->{$p->{name}}}), "\n";
	}
}
sub _export_shape {
	my ($fh, $container, $p) = @_;
	
	my $count = $#{$container->{$p->{name}}} + 1;
	print $fh $p->{name}.' = '.$count."\n";
	my $i = 0;
	foreach my $shape (@{$container->{$p->{name}}}) {
		my $id = "shape_$i";
		if ($$shape{type} == 0) {
			print $fh "$id:type = sphere\n";
			print $fh "$id:offset = ", join(',', @{$$shape{sphere}}[0 .. 2]), "\n";
			print $fh "$id:radius = $$shape{sphere}[3]\n";
		} elsif ($$shape{type} == 1) {
			print $fh "$id:type = box\n";
			print $fh "$id:axis_x = ", join(',', @{$$shape{box}}[0 .. 2]), "\n";
			print $fh "$id:axis_y = ", join(',', @{$$shape{box}}[3 .. 5]), "\n";
			print $fh "$id:axis_z = ", join(',', @{$$shape{box}}[6 .. 8]), "\n";
			print $fh "$id:offset = ", join(',', @{$$shape{box}}[9 .. 11]), "\n";
		}
		$i++;
	}
}
sub _export_skeleton {
	my ($fh, $container, $p) = @_;

	print $fh 'bones_mask = '.join(',', @{$container->{bones_mask}})."\n";
	print $fh "root_bone = $container->{root_bone}\n";
	print $fh 'bbox_min = '.join(',', @{$container->{bbox_min}})."\n";
	print $fh 'bbox_max = '.join(',', @{$container->{bbox_max}})."\n";
	my $count = $#{$container->{bones}} + 1;
	print $fh "bones_count = $count\n";
	my $i = 0;
	foreach my $bone (@{$container->{bones}}) {
		my $id = "bone_$i";
		print $fh "$id:ph_position = ".join(',', @{$bone->{ph_position}})."\n";
		print $fh "$id:ph_rotation = ".join(',', @{$bone->{ph_rotation}})."\n";
		print $fh "$id:enabled = $bone->{enabled}\n\n";		
		$i++;
	}
}
sub _export_supplies {
	my ($fh, $container, $p) = @_;
	
	my $count = $#{$container->{$p->{name}}} + 1;
	print $fh $p->{name}.' = '.$count."\n";
	return if $count == 0;
	my $i = 0;
	foreach my $sect (@{$container->{$p->{name}}}) {
		my $id = "sup_$i";
		print $fh "$id:section_name = $sect->{section_name}\n";
		print $fh "$id:item_count = $$sect{item_count}\n";
		print $fh "$id:min_factor = $$sect{min_factor}\n";
		print $fh "$id:max_factor = $$sect{max_factor}\n";
		print $fh "\n";
		$i++;
	}
}
sub _export_artefact_spawns {
	my ($fh, $container, $p) = @_;
	
	my $count = $#{$container->{$p->{name}}} + 1;
	print $fh $p->{name}.' = '.$count."\n";
	return if $count == 0;
	my $i = 0;
	foreach my $sect (@{$container->{$p->{name}}}) {
		my $id = "art_$i";
		print $fh "$id:section_name = $$sect{section_name}\n";
		print $fh "$id:weight = $$sect{weight}\n";
		print $fh "\n";
		$i++;
	}
}
sub _export_ordered_artefacts {
	my ($fh, $container, $p) = @_;
	
	my $i = 0;
	my $k = 0;
	my $count = $#{$container->{$p->{name}}} + 1;
	print $fh $p->{name}.' = '.$count."\n";
	return if $count == 0;
	foreach my $sect (@{$container->{$p->{name}}}) {
		my $id = "unknown_section_$i";
		print $fh "$id:unknown_string = $sect->{name}\n";
		print $fh "$id:unknown_number = $sect->{number}\n";
		my $count = $#{$sect->{af_sects}} + 1;
		print $fh "$id:artefact_sections = ".$count."\n";
		$k = 0;
		foreach my $af (@{$sect->{af_sects}}) {
			my $af_id = "artefact_section_$i";
			print $fh "$id:$af_id:artefact_name = $af->{af_section}\n";
			print $fh "$id:$af_id:number_1 = $af->{unk_num1}\n";
			print $fh "$id:$af_id:number_2 = $af->{unk_num2}\n";
			$k++;
		}
		$i++;
	}
}
sub _export_ctime {
	my ($fh, $name, $time) = @_;
#	print $time."\n";
	return if $time == 0;
	my @time = $time->get_all();
	if ($time[0] != 2000) {
		if ($time[0] != 2255) {
			print $fh "$name = ", join(':', @time), "\n";
		} else {
			print $fh "$name = 255\n";
		}
	}
}
sub _export_jobs {
	my ($fh, $container, $p) = @_;
	
	my $count = $#{$container->{$p->{name}}} + 1;
	print $fh $p->{name}.' = '.$count."\n";
	return if $count == 0;
	my $i = 0;
	foreach my $job (@{$container->{$p->{name}}}) {
		my $id = "job_$i";
		print $fh "$id:job_begin = $job->{job_begin}\n";
		print $fh "$id:job_fill_idle = $job->{job_fill_idle}\n";
		print $fh "$id:job_idle_after_death_end = $job->{job_idle_after_death_end}\n\n";
		$i++;
	}
}
sub _export_npc_info {
	if ($_[1]->{version} >= 122) {
		_export_npc_info_cop(@_);
	} elsif ($_[1]->{version} >= 117) {
		_export_npc_info_soc(@_);
	} else {
		_export_npc_info_old(@_);
	}
}
sub _export_npc_info_old {
	my ($fh, $container, $p) = @_;
	
	my $count = $#{$container->{$p->{name}}} + 1;
	print $fh $p->{name}.' = '.$count."\n";
	return if $count == 0;
	my $i = 0;
	foreach my $info (@{$container->{$p->{name}}}) {
		my $id = "info_$i";
		print $fh "$id:o_id = $info->{o_id}\n";
		print $fh "$id:group = $$info{group}\n";
		print $fh "$id:squad = $$info{squad}\n";
		print $fh "$id:move_offline = $$info{move_offline}\n";
		print $fh "$id:switch_offline = $$info{switch_offline}\n";
		_export_ctime($fh, "$id:stay_end", $$info{stay_end});
		print $fh "$id:jobN = $info->{jobN}\n" if $container->{script_version} >= 1 && $container->{gulagN} != 0;
		print $fh "\n";
		$i++;
	}
}
sub _export_npc_info_soc {
	my ($fh, $container, $p) = @_;
	
	my $count = $#{$container->{$p->{name}}} + 1;
	print $fh $p->{name}.' = '.$count."\n";
	return if $count == 0;
	my $i = 0;
	foreach my $info (@{$container->{$p->{name}}}) {
		my $id = "info_$i";
		print $fh "$id:o_id = $info->{o_id}\n";
		print $fh "$id:o_group = $$info{o_group}\n";
		print $fh "$id:o_squad = $$info{o_squad}\n";
		print $fh "$id:exclusive = $$info{exclusive}\n";
		_export_ctime($fh, "$id:stay_end", $$info{stay_end});
		print $fh "$id:Object_begin_job = $info->{Object_begin_job}\n";
		print $fh "$id:Object_didnt_begin_job = $$info{Object_didnt_begin_job}\n" if $container->{script_version} > 4;
		print $fh "$id:jobN = $$info{jobN}\n\n";
		$i++;
	}
}
sub _export_npc_info_cop {
	my ($fh, $container, $p) = @_;

	my $count = $#{$container->{$p->{name}}} + 1;
	print $fh $p->{name}.' = '.$count."\n";
	return if $count == 0;
	my $i = 0;
	foreach my $info (@{$container->{$p->{name}}}) {
		my $id = "info_$i";
		print $fh "$id:id = $info->{id}\n";
		print $fh "$id:job_prior = $$info{job_prior}\n";
		print $fh "$id:job_id = $$info{job_id}\n";
		print $fh "$id:begin_job = $$info{begin_job}\n";
		print $fh "$id:need_job = $$info{need_job}\n\n";
		$i++;
	}
}
sub _export_covers {
	my ($fh, $container, $p) = @_;
	
	my $count = $#{$container->{$p->{name}}} + 1;
	print $fh $p->{name}.' = '.$count."\n";
	return if $count == 0;
	my $i = 0;
	foreach my $cover (@{$container->{$p->{name}}}) {
		my $id = "cover_$i";
		print $fh "$id:npc_id = $cover->{npc_id}\n";
		print $fh "$id:cover_vertex_id = $$cover{cover_vertex_id}\n";
		print $fh "$id:cover_position = ".join(',', @{$$cover{cover_position}})."\n";
		print $fh "$id:look_pos = ".join(',', @{$$cover{look_pos}})."\n";
		print $fh "$id:is_smart_cover = $cover->{is_smart_cover}\n\n";
		$i++;
	}
}
sub _export_squads {
	my ($fh, $container, $p) = @_;
	
	my $count = $#{$container->{$p->{name}}} + 1;
	print $fh "\n; squads\n";
	print $fh $p->{name}.' = '.$count."\n";
	return if $count == 0;
	my $i = 0;
	foreach my $squad (@{$container->{$p->{name}}}) {
		my $id = "squad_$i";
		print $fh "$id:squad_name = $squad->{squad_name}\n";
		print $fh "$id:squad_stage = $$squad{squad_stage}\n";
		print $fh "$id:squad_prepare_shouted = $$squad{squad_prepare_shouted}\n";
		print $fh "$id:squad_attack_shouted = $$squad{squad_attack_shouted}\n";
		print $fh "$id:squad_attack_squad = $$squad{squad_attack_squad}\n";
		_export_ctime($fh, "$id:squad_inited_defend_time", $$squad{squad_inited_defend_time});
		_export_ctime($fh, "$id:squad_start_attack_wait", $$squad{squad_start_attack_wait});
		_export_ctime($fh, "$id:squad_last_defence_kill_time", $$squad{squad_last_defence_kill_time});
		print $fh "$id:squad_power = $squad->{squad_power}\n\n";
		$i++;
	}
}
sub _export_times {
	my ($fh, $container, $p) = @_;

	my $count = $#{$container->{$p->{name}}} + 1;
	print $fh $p->{name}.' = '.$count."\n";
	return if $count == 0;
	my $i = 0;
	foreach my $time (@{$container->{$p->{name}}}) {
		my $id = "time_$i";
		_export_ctime($fh, "$id", $time);
		$i++;
	}
}
sub _export_sim_squads {
	my ($fh, $container, $p) = @_;
	
	my $count = $#{$container->{$p->{name}}} + 1;
	print $fh $p->{name}.' = '.$count."\n";
	return if $count == 0;
	my $i = 0;
	foreach my $squad (@{$container->{$p->{name}}}) {
		my $id = "sim_squad_$i";
		print $fh "$id:squad_id = $squad->{squad_id}\n";
		print $fh "$id:settings_id = $$squad{settings_id}\n";
		print $fh "$id:is_scripted = $$squad{is_scripted}\n";
		if ($squad->{is_scripted} == 1) {
			_export_sim_squad_generic($fh, $squad, $id);
			print $fh "$id:next_target = $$squad{next_target}\n";
			print $fh "$id:need_free_update = $$squad{need_free_update}\n";
			print $fh "$id:relationship = $squad->{relationship}\n";
			print $fh "$id:sympathy = $squad->{sympathy}\n";
		}
		print $fh "\n";
		$i++;
	}	
}
sub _export_sim_squad_generic {
	my ($fh, $squad, $id) = @_;
	
	print $fh "$id:smart_id = $squad->{smart_id}\n";
	print $fh "$id:assigned_target_smart_id = $$squad{assigned_target_smart_id}\n";
	print $fh "$id:sim_combat_id = $$squad{sim_combat_id}\n";
	print $fh "$id:delayed_attack_task = $squad->{delayed_attack_task}\n";
	print $fh "$id:random_tasks = ".join(',', @{$squad->{random_tasks}})."\n";
	print $fh "$id:npc_count = $squad->{npc_count}\n";
	print $fh "$id:squad_power = $$squad{squad_power}\n";
	print $fh "$id:commander_id = $$squad{commander_id}\n";	
	print $fh "$id:squad_npc = ".join(',', @{$squad->{squad_npc}})."\n";	
	print $fh "$id:spoted_shouted = $squad->{spoted_shouted}\n";
	print $fh "$id:squad_power = $$squad{squad_power}\n";	
	_export_ctime($fh, "$id:last_action_timer", $$squad{last_action_timer});
	print $fh "$id:squad_attack_power = $$squad{squad_attack_power}\n";		
	print $fh "$id:class = $$squad{class}\n";		
	if (defined $squad->{class}) {
		if ($squad->{class} == 1) {
			#sim_attack_point
			print $fh "$id:dest_smrt_id = $squad->{dest_smrt_id}\n";
			print $fh "$id:major = $$squad{major}\n";
			print $fh "$id:target_power_value = $$squad{target_power_value}\n";
		} else {
			#sim_stay_point
			print $fh "$id:stay_defended = $squad->{stay_defended}\n";
			print $fh "$id:next_point_id = $$squad{next_point_id}\n";
			_export_ctime($fh, "$id:begin_time", $$squad{begin_time});
		}
	}
	
	print $fh "$id:items_spawned = $squad->{items_spawned}\n";
	_export_ctime($fh, "$id:bring_item_inited_time", $$squad{bring_item_inited_time});
	_export_ctime($fh, "$id:recover_item_inited_time", $$squad{recover_item_inited_time});	
}
sub _export_inited_tasks {
	my ($fh, $container, $p) = @_;
	
	my $count = $#{$container->{$p->{name}}} + 1;
	print $fh "\n; inited tasks\n";
	print $fh $p->{name}.' = '.$count."\n";
	return if $count == 0;
	my $i = 0;
	foreach my $task (@{$container->{$p->{name}}}) {
		my $id = "task_$i";
		print $fh "$id:base_id = $task->{base_id}\n";
		print $fh "$id:id = $task->{id}\n";
		print $fh "$id:type = $task->{type}\n";
		SWITCH: {
			($task->{type} == 0 || $task->{type} == 5) && do {_export_CStorylineTask($fh, $task, $id);last SWITCH;};
			$task->{type} == 1 && do {_export_CEliminateSmartTask($fh, $task, $id);last SWITCH;};
			$task->{type} == 2 && do {_export_CCaptureSmartTask($fh, $task, $id);last SWITCH;};
			($task->{type} == 3 || $task->{type} == 4) && do {_export_CDefendSmartTask($fh, $task, $id);last SWITCH;};
			$task->{type} == 6 && do {_export_CBringItemTask($fh, $task, $id);last SWITCH;};
			$task->{type} == 7 && do {_export_CRecoverItemTask($fh, $task, $id);last SWITCH;};
			$task->{type} == 8 && do {_export_CFindUpgradeTask($fh, $task, $id);last SWITCH;};
			$task->{type} == 9 && do {_export_CHideFromSurgeTask($fh, $task, $id);last SWITCH;};
			$task->{type} == 10 && do {_export_CEliminateSquadTask($fh, $task, $id);last SWITCH;};
		}
		print $fh "\n";
		$i++;
	}
}
sub _export_CGeneralTask {
	my ($fh, $task, $id) = @_;
	print $fh "$id:entity_id = $task->{entity_id}\n";
	print $fh "$id:prior = $task->{prior}\n";
	print $fh "$id:status = $task->{status}\n";	
	print $fh "$id:actor_helped = $task->{actor_helped}\n";
	print $fh "$id:community = $task->{community}\n";
	print $fh "$id:actor_come = $task->{actor_come}\n";	
	print $fh "$id:actor_ignore = $task->{actor_ignore}\n";
	_export_ctime($fh, "$id:inited_time", $task->{inited_time});
}
sub _export_CStorylineTask {
	my ($fh, $task, $id) = @_;
	_export_CGeneralTask(@_);
	print $fh "$id:target = $task->{target}\n";
}
sub _export_CEliminateSmartTask {
	my ($fh, $task, $id) = @_;
	_export_CGeneralTask(@_);
	print $fh "$id:target = $task->{target}\n";
	print $fh "$id:src_obj = $task->{src_obj}\n";
	print $fh "$id:faction = $task->{faction}\n";
}
sub _export_CCaptureSmartTask {
	my ($fh, $task, $id) = @_;
	_export_CGeneralTask(@_);
	print $fh "$id:target = $task->{target}\n";
	print $fh "$id:state = $task->{state}\n";
	print $fh "$id:counter_attack_community = $task->{counter_attack_community}\n";
	print $fh "$id:counter_squad = $task->{counter_squad}\n";
	print $fh "$id:src_obj = $task->{src_obj}\n";
	print $fh "$id:faction = $task->{faction}\n";
}
sub _export_CDefendSmartTask {
	my ($fh, $task, $id) = @_;
	_export_CGeneralTask(@_);
	print $fh "$id:target = $task->{target}\n";
	_export_ctime($fh, "$id:last_called_time", $task->{last_called_time});
}
sub _export_CBringItemTask {
	my ($fh, $task, $id) = @_;
	_export_CGeneralTask(@_);
	print $fh "$id:state = $task->{state}\n";
	print $fh "$id:ri_counter = $task->{ri_counter}\n";
	print $fh "$id:target = $task->{target}\n";
	print $fh "$id:squad_id = $task->{squad_id}\n";
	print $fh "$id:requested_items = ".($#{$task->{requested_items}} + 1)."\n";
	my $j = 0;
	foreach my $item (@{$task->{requested_items}}) {
		print $fh "$id:item_id_$j = $item->{id}\n";
		print $fh "$id:items_$j = ".join(',', @{$item->{requested_items}})."\n";	
		$j++;
	}
}
sub _export_CRecoverItemTask {
	my ($fh, $task, $id) = @_;
	_export_CGeneralTask(@_);
	print $fh "$id:state = $task->{state}\n";
	print $fh "$id:squad_id = $task->{squad_id}\n";
	print $fh "$id:target_obj_id = $task->{target_obj_id}\n";
	print $fh "$id:presence_requested_item = $task->{presence_requested_item}\n";
	print $fh "$id:requested_item = $task->{requested_item}\n";
}
sub _export_CFindUpgradeTask {
	my ($fh, $task, $id) = @_;
	_export_CGeneralTask(@_);
	print $fh "$id:state = $task->{state}\n";
	print $fh "$id:presence_requested_item = $task->{presence_requested_item}\n";
	print $fh "$id:requested_item = $task->{requested_item}\n";
}
sub _export_CHideFromSurgeTask {
	my ($fh, $task, $id) = @_;
	_export_CGeneralTask(@_);
	print $fh "$id:target = $task->{target}\n";
	print $fh "$id:wait_time = $task->{wait_time}\n";
	print $fh "$id:effector_started_time = $task->{effector_started_time}\n";
}
sub _export_CEliminateSquadTask {
	my ($fh, $task, $id) = @_;
	_export_CGeneralTask(@_);
	print $fh "$id:target = $task->{target}\n";
	print $fh "$id:src_obj = $task->{src_obj}\n";
}
sub _export_inited_find_upgrade_tasks {
	my ($fh, $container, $p) = @_;
	
	my $count = $#{$container->{$p->{name}}} + 1;
	print $fh "\n; inited 'find upgrade' tasks\n";
	print $fh $p->{name}.' = '.$count."\n";
	return if $count == 0;
	my $i = 0;
	foreach my $task (@{$container->{$p->{name}}}) {
		my $id = "upgrade_task_$i";
		print $fh "$id:k = $task->{k}\n";
		print $fh "$id:subtasks = ".($#{$task->{subtasks}} + 1)."\n";
		my $j = 0;
		foreach my $subtask (@{$task->{subtasks}}) {
			print $fh "$id:kk_$j = $subtask->{kk}\n";
			print $fh "$id:entity_id_$j = $subtask->{entity_id}\n";
			$j++;
		}
		$i++;
	}
}
sub _export_rewards {
	my ($fh, $container, $p) = @_;
	
	my $count = $#{$container->{$p->{name}}} + 1;
	print $fh "\n; rewards\n";
	print $fh $p->{name}.' = '.$count."\n";
	return if $count == 0;
	my $i = 0;
	foreach my $comm (@{$container->{$p->{name}}}) {
		my $id = "community_$i";
		print $fh "$id:community_name = $comm->{community}\n";
		print $fh "$id:rewards = ".($#{$comm->{rewards}} + 1)."\n";
		my $j = 0;
		foreach my $reward (@{$comm->{rewards}}) {
			if ($reward->{is_money} == 1) {
				print $fh "$id:reward_$j:money_amount = $reward->{amount}\n";
			} else {
				print $fh "$id:reward_$j:item_name = $reward->{item_name}\n";
			}
			$j++;
		}		
		$i++;
	}
	print $fh "\n";
}
sub _export_minigames {
	my ($fh, $container, $p) = @_;
	
	my $count = $#{$container->{$p->{name}}} + 1;
	print $fh "\n; minigames\n";
	print $fh $p->{name}.' = '.$count."\n";
	return if $count == 0;
	my $i = 0;
	foreach my $minigame (@{$container->{$p->{name}}}) {
		my $id = "minigame_$i";
		print $fh "$id:key = $minigame->{key}\n";
		print $fh "$id:profile = $minigame->{profile}\n";
		print $fh "$id:state = $minigame->{state}\n";
		if ($minigame->{profile} eq 'CMGCrowKiller') {
			print $fh "$id:param_highscore = $minigame->{param_highscore}\n";
			print $fh "$id:param_timer = $minigame->{param_timer}\n";
			print $fh "$id:param_win = $minigame->{param_win}\n";
			print $fh "$id:param_crows_to_kill = ".join(',', @{$minigame->{param_crows_to_kill}})."\n";
			print $fh "$id:param_money_multiplier = $minigame->{param_money_multiplier}\n";
			print $fh "$id:param_champion_multiplier = $minigame->{param_champion_multiplier}\n";
			print $fh "$id:param_selected = $minigame->{param_selected}\n";
			print $fh "$id:param_game_type = $minigame->{param_game_type}\n";
			print $fh "$id:high_score = $minigame->{high_score}\n";		
			print $fh "$id:timer = $minigame->{timer}\n";
			print $fh "$id:time_out = $minigame->{time_out}\n";
			print $fh "$id:killed_counter = $minigame->{killed_counter}\n";
			print $fh "$id:win = $minigame->{win}\n";
		} elsif ($minigame->{profile} eq 'CMGShooting') {
			print $fh "$id:param_game_type = $minigame->{param_game_type}\n";
			print $fh "$id:param_wpn_type = $minigame->{param_wpn_type}\n";
			print $fh "$id:param_stand_way = $minigame->{param_stand_way}\n";
			print $fh "$id:param_look_way = $minigame->{param_look_way}\n";		
			print $fh "$id:param_stand_way_back = $minigame->{param_stand_way_back}\n";
			print $fh "$id:param_look_way_back = $minigame->{param_look_way_back}\n";
			print $fh "$id:param_obj_name = $minigame->{param_obj_name}\n";
			print $fh "$id:param_is_u16 = $minigame->{param_is_u16}\n";
			if ($minigame->{param_is_u16} == 0) {
				print $fh "$id:param_win = $minigame->{param_win}\n";	
			} else {
				print $fh "$id:param_win = $minigame->{param_win}\n";	
			}	
			print $fh "$id:param_distance = $minigame->{param_distance}\n";
			print $fh "$id:param_ammo = $minigame->{param_ammo}\n";
			print $fh "$id:targets = ".($#{$minigame->{targets}} + 1)."\n";		
			my $j = 0;
			foreach my $target (@{$minigame->{targets}}) {
				print $fh "$id:target_$j = ".join(',', @$target)."\n";	
				$j++;				
			}
			print $fh "$id:param_target_counter = $minigame->{param_target_counter}\n";
			print $fh "$id:inventory_items = ".join(',', @{$minigame->{inventory_items}})."\n";		
			print $fh "$id:prev_time = $minigame->{prev_time}\n";
			print $fh "$id:type = $minigame->{type}\n";
			
			if ($minigame->{type} eq 'training' || $minigame->{type} eq 'points') {
				print $fh "$id:win = $minigame->{win}\n";
				print $fh "$id:ammo = $minigame->{ammo}\n";		
				print $fh "$id:cur_target = $minigame->{cur_target}\n";
				print $fh "$id:points = $minigame->{points}\n";
				print $fh "$id:ammo_counter = $minigame->{ammo_counter}\n";
			} elsif ($minigame->{type} eq 'count') {
				print $fh "$id:wpn_type = $minigame->{wpn_type}\n";
				print $fh "$id:win = $minigame->{win}\n";		
				print $fh "$id:ammo = $minigame->{ammo}\n";		
				print $fh "$id:targets = ".($#{$minigame->{targets}} + 1)."\n";						
				my $j = 0;
				foreach my $target (@{$minigame->{targets}}) {
					print $fh "$id:target_$j = ".join(',', @$target)."\n";	
					$j++;				
				}				
				print $fh "$id:distance = $minigame->{distance}\n";
				print $fh "$id:cur_target = $minigame->{cur_target}\n";		
				print $fh "$id:points = $minigame->{points}\n";
				print $fh "$id:scored = $minigame->{scored}\n";
				print $fh "$id:ammo_counter = $minigame->{ammo_counter}\n";						
			} elsif ($minigame->{type} eq 'three_hit_training') {
				print $fh "$id:wpn_type = $minigame->{wpn_type}\n";
				print $fh "$id:win = $minigame->{win}\n";		
				print $fh "$id:ammo = $minigame->{ammo}\n";
				print $fh "$id:targets = ".($#{$minigame->{targets}} + 1)."\n";		
				my $j = 0;
				foreach my $target (@{$minigame->{targets}}) {
					print $fh "$id:target_$j = ".join(',', @$target)."\n";	
					$j++;				
				}		
				print $fh "$id:distance = $minigame->{distance}\n";
				print $fh "$id:cur_target = $minigame->{cur_target}\n";		
				print $fh "$id:points = $minigame->{points}\n";
				print $fh "$id:scored = $minigame->{scored}\n";
				print $fh "$id:ammo_counter = $minigame->{ammo_counter}\n";	
				print $fh "$id:target_counter = $minigame->{target_counter}\n";
				print $fh "$id:target_hit = $minigame->{target_hit}\n";						
			} elsif ($minigame->{type} eq 'all_targets') {			
				print $fh "$id:wpn_type = $minigame->{wpn_type}\n";
				print $fh "$id:win = $minigame->{win}\n";		
				print $fh "$id:ammo = $minigame->{ammo}\n";
				print $fh "$id:targets = ".($#{$minigame->{targets}} + 1)."\n";		
				print $fh "$id:hitted_targets = ".($#{$minigame->{hitted_targets}} + 1)."\n";		
				my $j = 0;
				foreach my $target (@{$minigame->{targets}}) {
					print $fh "$id:target_$j = ".join(',', @$target)."\n";	
					$j++;				
				}	
				foreach my $target (@{$minigame->{hitted_targets}}) {
					print $fh "$id:hitted_target_$j = ".join(',', @$target)."\n";	
					$j++;				
				}					
				print $fh "$id:ammo_counter = $minigame->{ammo_counter}\n";
				print $fh "$id:time = $minigame->{time}\n";		
				print $fh "$id:target_counter = $minigame->{target_counter}\n";
				print $fh "$id:prev_time = $minigame->{prev_time}\n";
				print $fh "$id:more_targets = $minigame->{more_targets}\n";	
				print $fh "$id:last_target = $minigame->{last_target}\n";
			} elsif ($minigame->{type} eq 'count_on_time') {
				print $fh "$id:wpn_type = $minigame->{wpn_type}\n";
				print $fh "$id:win = $minigame->{win}\n";		
				print $fh "$id:ammo = $minigame->{ammo}\n";
				print $fh "$id:targets = ".($#{$minigame->{targets}} + 1)."\n";		
				my $j = 0;
				foreach my $target (@{$minigame->{targets}}) {
					print $fh "$id:target_$j = ".join(',', @$target)."\n";	
					$j++;				
				}					
				print $fh "$id:distance = $minigame->{distance}\n";
				print $fh "$id:cur_target = $minigame->{cur_target}\n";		
				print $fh "$id:points = $minigame->{points}\n";
				print $fh "$id:ammo_counter = $minigame->{ammo_counter}\n";
				print $fh "$id:time = $minigame->{time}\n";	
				print $fh "$id:prev_time = $minigame->{prev_time}\n";
			} elsif ($minigame->{type} eq 'ten_targets') {
				print $fh "$id:wpn_type = $minigame->{wpn_type}\n";
				print $fh "$id:win = $minigame->{win}\n";		
				print $fh "$id:ammo = $minigame->{ammo}\n";
				print $fh "$id:targets = ".($#{$minigame->{targets}} + 1)."\n";		
				my $j = 0;
				foreach my $target (@{$minigame->{targets}}) {
					print $fh "$id:target_$j = ".join(',', @$target)."\n";	
					$j++;				
				}					
				print $fh "$id:distance = $minigame->{distance}\n";
				print $fh "$id:cur_target = $minigame->{cur_target}\n";		
				print $fh "$id:points = $minigame->{points}\n";
				print $fh "$id:scored = $minigame->{scored}\n";
				print $fh "$id:ammo_counter = $minigame->{ammo_counter}\n";	
				print $fh "$id:time = $minigame->{time}\n";	
				print $fh "$id:prev_time = $minigame->{prev_time}\n";			
			} elsif ($minigame->{type} eq 'two_seconds_standing') {
				print $fh "$id:wpn_type = $minigame->{wpn_type}\n";
				print $fh "$id:win = $minigame->{win}\n";		
				print $fh "$id:ammo = $minigame->{ammo}\n";
				print $fh "$id:targets = ".($#{$minigame->{targets}} + 1)."\n";		
				my $j = 0;
				foreach my $target (@{$minigame->{targets}}) {
					print $fh "$id:target_$j = ".join(',', @$target)."\n";	
					$j++;				
				}					
				print $fh "$id:distance = $minigame->{distance}\n";
				print $fh "$id:cur_target = $minigame->{cur_target}\n";		
				print $fh "$id:points = $minigame->{points}\n";
				print $fh "$id:ammo_counter = $minigame->{ammo_counter}\n";	
				print $fh "$id:time = $minigame->{time}\n";	
				print $fh "$id:prev_time = $minigame->{prev_time}\n";			
			}
		}
		$i++;
		print $fh "\n";
	}
}

#import functions
sub import_properties {
	my $self = shift;
	my $section = shift;
	my $container = shift;
	
	fail("$section is undefined") unless defined $self->{sections_hash}{$section};
#	print "[$section]\n";
	foreach my $p (@_) {
#	print "$p->{name} = ";
		my $value = $self->value($section, $p->{name});
		my $format = format_for_number->{$p->{type}};
		defined $format					&& do {$self->_import_scalar($value, $container, $p); next;};
		($p->{type} eq 'sz')			&& do {$self->_import_string($value, $container, $p); next;};
		($p->{type} eq 'shape')			&& do {$self->_import_shape($section, $value, $container, $p); next;};
		($p->{type} eq 'skeleton')		&& do {$self->_import_skeleton($section, $value, $container, $p); next;};
		($p->{type} eq 'supplies')		&& do {$self->_import_supplies($section, $value, $container, $p); next;};
		($p->{type} =~ /afspawns/)		&& do {$self->_import_artefact_spawns($section, $value, $container, $p); next;};
		($p->{type} eq 'ordaf')			&& do {$self->_import_ordered_artefacts($section, $value, $container, $p); next;};
		($p->{type} eq 'CTime')			&& do {$container->{$p->{name}} = _import_ctime($value); next;};
		($p->{type} eq 'complex_time')	&& do {$container->{$p->{name}} = _import_ctime($value); next;};
		($p->{type} eq 'npc_info')		&& do {$self->_import_npc_info($section, $value, $container, $p); next;};
		#SOC
		($p->{type} eq 'jobs')			&& do {$self->_import_jobs($section, $value, $container, $p); next;};
		#CS
		($p->{type} eq 'covers')		&& do {$self->_import_covers($section, $value, $container, $p); next;};
		($p->{type} eq 'squads')		&& do {$self->_import_squads($section, $value, $container, $p); next;};
		($p->{type} eq 'sim_squads')	&& do {$self->_import_sim_squads($section, $value, $container, $p); next;};
		($p->{type} eq 'inited_tasks')		&& do {$self->_import_inited_tasks($section, $value, $container, $p); next;};
		($p->{type} eq 'inited_find_upgrade_tasks')		&& do {$self->_import_inited_find_upgrade_tasks($section, $value, $container, $p); next;};
		($p->{type} eq 'rewards')		&& do {$self->_import_rewards($section, $value, $container, $p); next;};
		($p->{type} eq 'minigames')		&& do {$self->_import_minigames($section, $value, $container, $p); next;};
		#COP
		($p->{type} eq 'times')			&& do {$self->_import_times($section, $value, $container, $p); next;};
		$self->_import_vector($value, $container, $p);
	}
}
sub _import_scalar {
	my ($self, $value, $container, $p) = @_;
	if (defined $value) {
		$value = hex($value) if ($value =~ /^\s*0x/);
		$container->{$p->{name}} = $value;
	} else {
		$container->{$p->{name}} = $p->{default};
	}	
}
sub _import_string {
	my ($self, $value, $container, $p) = @_;
	$container->{$p->{name}} = (defined $value) ? $value : $p->{default};
}
sub _import_vector {
	my ($self, $value, $container, $p) = @_;
	if ($p->{type} =~ /dumb/) {
		$container->{$p->{name}} = pack('H*', $value);	
	} else {
		@{$container->{$p->{name}}} = defined $value ? split(/,\s*/, $value) : @{$p->{default}};
	}
}
sub _import_shape {
	my ($self, $section, $value, $container, $p) = @_;
	fail("$p->{name} is undefined") unless defined $value;
	for (my $i = 0; $i < $value; $i++) {
		my $id = "shape_$i";
		my $shape = {};
		my $type = $self->value($section, "$id:type") or fail("no type in $section\n");
		my $offset = $self->value($section, "$id:offset");
		if ($type eq "sphere") {
			my $radius = $self->value($section, "$id:radius") or fail("no radius in $section\n");
			$shape->{type} = 0;
			@{$shape->{sphere}} = (split(/,/, $offset), $radius);
		} elsif ($type eq "box") {
			$shape->{type} = 1;
			my $axis_x = $self->value($section, "$id:axis_x") or fail("no axis_x in $section\n");
			my $axis_y = $self->value($section, "$id:axis_y") or fail("no axis_y in $section\n");
			my $axis_z = $self->value($section, "$id:axis_z") or fail("no axis_z in $section\n");
			push @{$shape->{box}}, split(/,/, $axis_x), split(/,/, $axis_y);
			push @{$shape->{box}}, split(/,/, $axis_z), split(/,/, $offset);
		} else {
			fail("unknown shape type in $section\n");
		}
		push @{$container->{$p->{name}}}, $shape;
	}
}
sub _import_skeleton {
	my ($self, $section, $value, $container, $p) = @_;
	@{$container->{bones_mask}} = split (/,\s*/,$self->value($section, 'bones_mask'));
	$container->{root_bone} = $self->value($section, 'root_bone');
	@{$container->{bbox_min}} = split (/,\s*/,$self->value($section, 'bbox_min'));
	@{$container->{bbox_max}} = split (/,\s*/,$self->value($section, 'bbox_max'));
	my $count = $self->value($section, 'bones_count');
	for (my $i = 0; $i < $count; $i++) {
		my $bone = {};
		@{$bone->{ph_position}} = split (/,\s*/,$self->value($section, "bone_$i:ph_position"));
		@{$bone->{ph_rotation}} = split (/,\s*/,$self->value($section, "bone_$i:ph_rotation"));
		$bone->{enabled} = $self->value($section, "bone_$i:enabled");
		push @{$container->{bones}}, $bone;
	}
}
sub _import_supplies {
	my ($self, $section, $value, $container, $p) = @_;
	return if (!defined $value or $value == 0);
	for (my $i = 0; $i < $value; $i++) {
		my $item = {};
		$item->{section_name} = $self->value($section, "sup_$i:section_name");
		$item->{item_count} = $self->value($section, "sup_$i:item_count");
		$item->{min_factor} = $self->value($section, "sup_$i:min_factor");
		$item->{max_factor} = $self->value($section, "sup_$i:max_factor");
		push @{$container->{$p->{name}}}, $item;
	}
}
sub _import_artefact_spawns {
	my ($self, $section, $value, $container, $p) = @_;
	return if (!defined $value or $value == 0);
	for (my $i = 0; $i < $value; $i++) {
		my $item = {};
		$item->{section_name} = $self->value($section, "art_$i:section_name");
		$item->{weight} = $self->value($section, "art_$i:weight");
		push @{$container->{$p->{name}}}, $item;
	}
}
sub _import_ordered_artefacts {
	my ($self, $section, $value, $container, $p) = @_;
	return if (!defined $value or $value == 0);
	for (my $i = 0; $i < $value; $i++) {
		my $id = "unknown_section_$i";
		my $item = {};
		$item->{unknown_string} = $self->value($section, "$id:unknown_string");
		$item->{unknown_number} = $self->value($section, "$id:unknown_number");
		my $count = $self->value($section, "$id:artefact_sections");
		for (my $j = 0; $j < $value; $j++) {
			my $art = {};
			my $sID = "$id:artefact_section_$j";
			$art->{artefact_name} = $self->value($section, "$sID:artefact_name");
			$art->{number_1} = $self->value($section, "$sID:number_1");
			$art->{number_2} = $self->value($section, "$sID:number_2");
			push @{$item->{af_sects}}, $art;
		}
		push @{$container->{$p->{name}}}, $item;
	}
}
sub _import_ctime {
	my ($value) = @_;
	return 0 if !defined $value;
	my @time = split(/:\s*/, $value);
	$time[0] -= 2000 if $time[0] != 255;
	my $time = stkutils::math->create('CTime');
	$time->set(@time);
	return $time;
}
sub _import_jobs {
	my ($self, $section, $value, $container, $p) = @_;
	return if (!defined $value or $value == 0);
	for (my $i = 0; $i < $value; $i++) {
		my $job = {};
		$job->{job_begin} = $self->value($section, "job_$i:job_begin");
		$job->{job_fill_idle} = $self->value($section, "job_$i:job_fill_idle");
		$job->{job_idle_after_death_end} = $self->value($section, "job_$i:job_idle_after_death_end");
		push @{$container->{$p->{name}}}, $job;
	}
}
sub _import_npc_info {
	if ($_[3]->{version} >= 122) {
		_import_npc_info_cop(@_);
	} elsif ($_[3]->{version} >= 117) {
		_import_npc_info_soc(@_);
	} else {
		_import_npc_info_old(@_);
	}
}
sub _import_npc_info_old {
	my ($self, $section, $value, $container, $p) = @_;
	return if (!defined $value or $value == 0);
	for (my $i = 0; $i < $value; $i++) {
		my $info = {};
		$info->{o_id} = $self->value($section, "info_$i:o_id");
		$info->{group} = $self->value($section, "info_$i:group");
		$info->{squad} = $self->value($section, "info_$i:squad");
		$info->{move_offline} = $self->value($section, "info_$i:move_offline");
		$info->{switch_offline} = $self->value($section, "info_$i:switch_offline");
		$info->{stay_end} = _import_ctime($self->value($section, "info_$i:stay_end"));
		$info->{jobN} = $self->value($section, "info_$i:Object_didnt_begin_job") if $container->{script_version} >= 1 && $container->{gulagN} != 0;
		push @{$container->{$p->{name}}}, $info;
	}
}
sub _import_npc_info_soc {
	my ($self, $section, $value, $container, $p) = @_;
	return if (!defined $value or $value == 0);
	for (my $i = 0; $i < $value; $i++) {
		my $info = {};
		$info->{o_id} = $self->value($section, "info_$i:o_id");
		$info->{o_group} = $self->value($section, "info_$i:o_group");
		$info->{o_squad} = $self->value($section, "info_$i:o_squad");
		$info->{exclusive} = $self->value($section, "info_$i:exclusive");
		$info->{stay_end} = _import_ctime($self->value($section, "info_$i:stay_end"));
		$info->{Object_begin_job} = $self->value($section, "info_$i:Object_begin_job");
		$info->{Object_didnt_begin_job} = $self->value($section, "info_$i:Object_didnt_begin_job") if $container->{script_version} > 4;
		$info->{jobN} = $self->value($section, "info_$i:jobN");
		push @{$container->{$p->{name}}}, $info;
	}
}
sub _import_npc_info_cop {
	my ($self, $section, $value, $container, $p) = @_;
	return if (!defined $value or $value == 0);
	for (my $i = 0; $i < $value; $i++) {
		my $info = {};
		$info->{id} = $self->value($section, "info_$i:id");
		$info->{job_prior} = $self->value($section, "info_$i:job_prior");
		$info->{job_id} = $self->value($section, "info_$i:job_id");
		$info->{begin_job} = $self->value($section, "info_$i:begin_job");
		$info->{need_job} = $self->value($section, "info_$i:need_job");
		push @{$container->{$p->{name}}}, $info;
	}
}
sub _import_covers {
	my ($self, $section, $value, $container, $p) = @_;
	return if (!defined $value or $value == 0);
	for (my $i = 0; $i < $value; $i++) {
		my $cover = {};
		$cover->{npc_id} = $self->value($section, "cover_$i:npc_id");
		$cover->{cover_vertex_id} = $self->value($section, "cover_$i:cover_vertex_id");
		@{$cover->{cover_position}} = split(/,\s*/, $self->value($section, "cover_$i:cover_position"));
		@{$cover->{look_pos}} = split(/,\s*/, $self->value($section, "cover_$i:look_pos"));
		$cover->{is_smart_cover} = $self->value($section, "cover_$i:is_smart_cover");
		push @{$container->{$p->{name}}}, $cover;
	}
}
sub _import_squads {
	my ($self, $section, $value, $container, $p) = @_;
	return if (!defined $value or $value == 0);
	for (my $i = 0; $i < $value; $i++) {
		my $squad = {};
		$squad->{squad_name} = $self->value($section, "squad_$i:squad_name");
		$squad->{squad_stage} = $self->value($section, "squad_$i:squad_stage");
		$squad->{squad_prepare_shouted} = $self->value($section, "squad_$i:squad_prepare_shouted");
		$squad->{squad_attack_shouted} = $self->value($section, "squad_$i:squad_attack_shouted");
		$squad->{squad_attack_squad} = $self->value($section, "squad_$i:squad_attack_squad");
		$squad->{squad_inited_defend_time} = _import_ctime($self->value($section, "squad_$i:squad_inited_defend_time"));
		$squad->{squad_start_attack_wait} = _import_ctime($self->value($section, "squad_$i:squad_start_attack_wait"));
		$squad->{squad_last_defence_kill_time} = _import_ctime($self->value($section, "squad_$i:squad_last_defence_kill_time"));
		$squad->{squad_power} = $self->value($section, "squad_$i:squad_power");
		push @{$container->{$p->{name}}}, $squad;
	}
}
sub _import_times {
	my ($self, $section, $value, $container, $p) = @_;
	return if (!defined $value or $value == 0);
	for (my $i = 0; $i < $value; $i++) {
		my $time = _import_ctime($self->value($section, "time_$i"));
		push @{$container->{$p->{name}}}, $time;
	}
}
sub _import_sim_squads {
	my ($self, $section, $value, $container, $p) = @_;
	return if (!defined $value or $value == 0);
	for (my $i = 0; $i < $value; $i++) {
		my $squad = {};
		$squad->{squad_id} = $self->value($section, "sim_squad_$i:squad_id");
		$squad->{settings_id} = $self->value($section, "sim_squad_$i:settings_id");
		$squad->{is_scripted} = $self->value($section, "sim_squad_$i:is_scripted");
		if ($squad->{is_scripted} == 1) {
			$self->_import_sim_squad_generic($section, $squad, $i);
			$squad->{next_target} = $self->value($section, "sim_squad_$i:next_target");
			$squad->{need_free_update} = $self->value($section, "sim_squad_$i:need_free_update");
			$squad->{relationship} = $self->value($section, "sim_squad_$i:relationship");
			$squad->{sympathy} = $self->value($section, "sim_squad_$i:sympathy");
		}
		push @{$container->{$p->{name}}}, $squad;
	}
}
sub _import_sim_squad_generic {
	my ($self, $section, $squad, $i) = @_;

	$squad->{smart_id} = $self->value($section, "sim_squad_$i:smart_id");
	$squad->{assigned_target_smart_id} = $self->value($section, "sim_squad_$i:assigned_target_smart_id");
	$squad->{sim_combat_id} = $self->value($section, "sim_squad_$i:sim_combat_id");
	$squad->{delayed_attack_task} = $self->value($section, "sim_squad_$i:delayed_attack_task");
	@{$squad->{random_tasks}} = split /,/, $self->value($section, "sim_squad_$i:random_tasks");
	$squad->{npc_count} = $self->value($section, "sim_squad_$i:npc_count");
	$squad->{squad_power} = $self->value($section, "sim_squad_$i:squad_power");
	$squad->{commander_id} = $self->value($section, "sim_squad_$i:commander_id");
	@{$squad->{squad_npc}} = split /,/, $self->value($section, "sim_squad_$i:squad_npc");	
	$squad->{spoted_shouted} = $self->value($section, "sim_squad_$i:spoted_shouted");
	$squad->{squad_power} = $self->value($section, "sim_squad_$i:squad_power");
	$squad->{last_action_timer} = _import_ctime($self->value($section, "sim_squad_$i:last_action_timer"));
	$squad->{squad_attack_power} = $self->value($section, "sim_squad_$i:squad_attack_power");
	$squad->{class} = $self->value($section, "sim_squad_$i:class");
	if (defined $squad->{class}) {
		if ($squad->{class} == 1) {
			#sim_attack_point
			$squad->{dest_smrt_id} = $self->value($section, "sim_squad_$i:dest_smrt_id");
			$squad->{major} = $self->value($section, "sim_squad_$i:major");
			$squad->{target_power_value} = $self->value($section, "sim_squad_$i:target_power_value");
		} else {
			#sim_stay_point
			$squad->{stay_defended} = $self->value($section, "sim_squad_$i:stay_defended");
			$squad->{next_point_id} = $self->value($section, "sim_squad_$i:next_point_id");
			$squad->{begin_time} = _import_ctime($self->value($section, "sim_squad_$i:begin_time"));
		}
	}
	$squad->{items_spawned} = $self->value($section, "sim_squad_$i:items_spawned");
	$squad->{bring_item_inited_time} = _import_ctime($self->value($section, "sim_squad_$i:bring_item_inited_time"));
	$squad->{recover_item_inited_time} = _import_ctime($self->value($section, "sim_squad_$i:recover_item_inited_time"));
}
sub _import_inited_tasks {
	my ($self, $section, $value, $container, $p) = @_;
	return if (!defined $value or $value == 0);
	for (my $i = 0; $i < $value; $i++) {
		my $task = {};
		$task->{base_id} = $self->value($section, "task_$i:base_id");
		$task->{id} = $self->value($section, "task_$i:id");
		$task->{type} = $self->value($section, "task_$i:type");
		SWITCH: {
			($task->{type} == 0 || $task->{type} == 5) && do {$self->_import_CStorylineTask($task, $section, $i);last SWITCH;};
			$task->{type} == 1 && do {$self->_import_CEliminateSmartTask($task, $section, $i);last SWITCH;};
			$task->{type} == 2 && do {$self->_import_CCaptureSmartTask($task, $section, $i);last SWITCH;};
			($task->{type} == 3 || $task->{type} == 4) && do {$self->_import_CDefendSmartTask($task, $section, $i);last SWITCH;};
			$task->{type} == 6 && do {$self->_import_CBringItemTask($task, $section, $i);last SWITCH;};
			$task->{type} == 7 && do {$self->_import_CRecoverItemTask($task, $section, $i);last SWITCH;};
			$task->{type} == 8 && do {$self->_import_CFindUpgradeTask($task, $section, $i);last SWITCH;};
			$task->{type} == 9 && do {$self->_import_CHideFromSurgeTask($task, $section, $i);last SWITCH;};
			$task->{type} == 10 && do {$self->_import_CEliminateSquadTask($task, $section, $i);last SWITCH;};
		}
		push @{$container->{$p->{name}}}, $task;
	}
}
sub _import_CGeneralTask {
	my ($self, $task, $section, $i) = @_;
	$task->{entity_id} = $self->value($section, "task_$i:entity_id");
	$task->{prior} = $self->value($section, "task_$i:prior");
	$task->{status} = $self->value($section, "task_$i:status");
	$task->{actor_helped} = $self->value($section, "task_$i:actor_helped");
	$task->{community} = $self->value($section, "task_$i:community");
	$task->{actor_come} = $self->value($section, "task_$i:actor_come");
	$task->{actor_ignore} = $self->value($section, "task_$i:actor_ignore");
	$task->{inited_time} = _import_ctime($self->value($section, "task_$i:inited_time"));
}
sub _import_CStorylineTask {
	my $self = shift;
	my ($task, $section, $i) = @_;
	$self->_import_CGeneralTask(@_);
	$task->{target} = $self->value($section, "task_$i:target");
}
sub _import_CEliminateSmartTask {
	my $self = shift;
	my ($task, $section, $i) = @_;
	_import_CGeneralTask(@_);
	$task->{target} = $self->value($section, "task_$i:target");
	$task->{src_obj} = $self->value($section, "task_$i:src_obj");
	$task->{faction} = $self->value($section, "task_$i:faction");
}
sub _import_CCaptureSmartTask {
	my $self = shift;
	my ($task, $section, $i) = @_;
	_import_CGeneralTask(@_);
	$task->{target} = $self->value($section, "task_$i:target");
	$task->{state} = $self->value($section, "task_$i:state");
	$task->{counter_attack_community} = $self->value($section, "task_$i:counter_attack_community");
	$task->{counter_squad} = $self->value($section, "task_$i:counter_squad");
	$task->{src_obj} = $self->value($section, "task_$i:src_obj");
	$task->{faction} = $self->value($section, "task_$i:faction");
}
sub _import_CDefendSmartTask {
	my $self = shift;
	my ($task, $section, $i) = @_;
	$self->_import_CGeneralTask(@_);
	$task->{target} = $self->value($section, "task_$i:target");
	$task->{last_called_time} = _import_ctime($self->value($section, "task_$i:last_called_time"));
}
sub _import_CBringItemTask {
	my $self = shift;
	my ($task, $section, $i) = @_;
	$self->_import_CGeneralTask(@_);
	$task->{target} = $self->value($section, "task_$i:target");
	$task->{state} = $self->value($section, "task_$i:state");
	$task->{ri_counter} = $self->value($section, "task_$i:ri_counter");
	$task->{squad_id} = $self->value($section, "task_$i:squad_id");
	my $count = $self->value($section, "task_$i:requested_items");
	for (my $j = 0; $j < $count; $j++) {
		my $item = {};
		$item->{id} = $self->value($section, "task_$i:item_id_$j");
		@{$item->{requested_items}} = split  /,/, $self->value($section, "task_$i:items_$j");
		push @{$task->{requested_items}}, $item;
	}
}
sub _import_CRecoverItemTask {
	my $self = shift;
	my ($task, $section, $i) = @_;
	$self->_import_CGeneralTask(@_);
	$task->{state} = $self->value($section, "task_$i:state");
	$task->{squad_id} = $self->value($section, "task_$i:squad_id");
	$task->{target_obj_id} = $self->value($section, "task_$i:target_obj_id");
	$task->{presence_requested_item} = $self->value($section, "task_$i:presence_requested_item");
	$task->{requested_item} = $self->value($section, "task_$i:requested_item");
}
sub _import_CFindUpgradeTask {
	my $self = shift;
	my ($task, $section, $i) = @_;
	$self->_import_CGeneralTask(@_);
	$task->{state} = $self->value($section, "task_$i:state");
	$task->{presence_requested_item} = $self->value($section, "task_$i:presence_requested_item");
	$task->{requested_item} = $self->value($section, "task_$i:requested_item");
}
sub _import_CHideFromSurgeTask {
	my $self = shift;
	my ($task, $section, $i) = @_;
	$self->_import_CGeneralTask(@_);
	$task->{target} = $self->value($section, "task_$i:target");
	$task->{wait_time} = $self->value($section, "task_$i:wait_time");
	$task->{effector_started_time} = $self->value($section, "task_$i:effector_started_time");
}
sub _import_CEliminateSquadTask {
	my $self = shift;
	my ($task, $section, $i) = @_;
	$self->_import_CGeneralTask(@_);
	$task->{target} = $self->value($section, "task_$i:target");
	$task->{src_obj} = $self->value($section, "task_$i:src_obj");
}
sub _import_inited_find_upgrade_tasks {
	my ($self, $section, $value, $container, $p) = @_;
	
	return if (!defined $value or $value == 0);
	for (my $i = 0; $i < $value; $i++) {
		my $task = {};
		$task->{k} = $self->value($section, "task_$i:k");
		my $count = $self->value($section, "task_$i:subtasks"); 
		for (my $j = 0; $j < $count; $j++) {
			my $subtask = {};
			$subtask->{k} = $self->value($section, "task_$i:kk_$j");
			$subtask->{entity_id} = $self->value($section, "task_$i:entity_id_$j");
			push @{$task->{subtasks}}, $subtask;
		}
		push @{$container->{$p->{name}}}, $task;
	}
}
sub _import_rewards {
	my ($self, $section, $value, $container, $p) = @_;
	
	return if (!defined $value or $value == 0);
	for (my $i = 0; $i < $value; $i++) {
		my $comm = {};
		$comm->{community} = $self->value($section, "community_$i:community_name");
		my $count = $self->value($section, "community_$i:rewards"); 
		for (my $j = 0; $j < $count; $j++) {
			my $reward = {};
			if (defined $self->value($section, "community_$i:reward_$j:money_amount")) {
				$reward->{amount} = $self->value($section, "community_$i:reward_$j:money_amount");
			} else {
				$reward->{item_name} = $self->value($section, "community_$i:reward_$j:item_name");
			}
			push @{$comm->{rewards}}, $reward;
		}	
		push @{$container->{$p->{name}}}, $comm;
	}
}
sub _import_minigames {
	my ($self, $section, $value, $container, $p) = @_;
	
	return if (!defined $value or $value == 0);
	for (my $i = 0; $i < $value; $i++) {
		my $minigame = {};
		$minigame->{key} = $self->value($section, "minigame_$i:key");
		$minigame->{profile} = $self->value($section, "minigame_$i:profile");
		$minigame->{state} = $self->value($section, "minigame_$i:state");
		if ($minigame->{profile} eq 'CMGCrowKiller') {
			$minigame->{param_highscore} = $self->value($section, "minigame_$i:param_highscore");
			$minigame->{param_timer} = $self->value($section, "minigame_$i:param_timer");
			$minigame->{param_win} = $self->value($section, "minigame_$i:param_win");		
			@{$minigame->{param_crows_to_kill}} = split /,/, $self->value($section, "minigame_$i:param_crows_to_kill");
			$minigame->{param_money_multiplier} = $self->value($section, "minigame_$i:param_money_multiplier");
			$minigame->{param_champion_multiplier} = $self->value($section, "minigame_$i:param_champion_multiplier");		
			$minigame->{param_selected} = $self->value($section, "minigame_$i:param_selected");
			$minigame->{param_game_type} = $self->value($section, "minigame_$i:param_game_type");
			$minigame->{high_score} = $self->value($section, "minigame_$i:high_score");
			$minigame->{timer} = $self->value($section, "minigame_$i:timer");
			$minigame->{time_out} = $self->value($section, "minigame_$i:time_out");
			$minigame->{killed_counter} = $self->value($section, "minigame_$i:killed_counter");		
			$minigame->{win} = $self->value($section, "minigame_$i:win");	
		} elsif ($minigame->{profile} eq 'CMGShooting') {
			$minigame->{param_game_type} = $self->value($section, "minigame_$i:param_game_type");
			$minigame->{param_wpn_type} = $self->value($section, "minigame_$i:param_wpn_type");
			$minigame->{param_stand_way} = $self->value($section, "minigame_$i:param_stand_way");
			$minigame->{param_look_way} = $self->value($section, "minigame_$i:param_look_way");		
			$minigame->{param_stand_way_back} = $self->value($section, "minigame_$i:param_stand_way_back");
			$minigame->{param_look_way_back} = $self->value($section, "minigame_$i:param_look_way_back");		
			$minigame->{param_obj_name} = $self->value($section, "minigame_$i:param_obj_name");
			$minigame->{param_is_u16} = $self->value($section, "minigame_$i:param_is_u16");
			$minigame->{param_win} = $self->value($section, "minigame_$i:param_win");
			$minigame->{param_distance} = $self->value($section, "minigame_$i:param_distance");
			$minigame->{param_ammo} = $self->value($section, "minigame_$i:param_ammo");
			my $count = $self->value($section, "minigame_$i:targets");
			for (my $j = 0; $j < $count; $j++) {
				push @{$minigame->{targets}}, \split(/,/, $self->value($section, "minigame_$i:target_$j"));
			}
			$minigame->{param_target_counter} = $self->value($section, "minigame_$i:param_target_counter");
			@{$minigame->{inventory_items}} = split /,/, $self->value($section, "minigame_$i:inventory_items");	
			$minigame->{prev_time} = $self->value($section, "minigame_$i:prev_time");	
			$minigame->{type} = $self->value($section, "minigame_$i:type");	
			if ($minigame->{type} eq 'training' || $minigame->{type} eq 'points') {
				$minigame->{win} = $self->value($section, "minigame_$i:win");
				$minigame->{ammo} = $self->value($section, "minigame_$i:ammo");
				$minigame->{cur_target} = $self->value($section, "minigame_$i:cur_target");		
				$minigame->{points} = $self->value($section, "minigame_$i:points");
				$minigame->{ammo_counter} = $self->value($section, "minigame_$i:ammo_counter");		
				$minigame->{param_obj_name} = $self->value($section, "minigame_$i:param_obj_name");
			} elsif ($minigame->{type} eq 'count') {
				$minigame->{wpn_type} = $self->value($section, "minigame_$i:wpn_type");
				$minigame->{win} = $self->value($section, "minigame_$i:win");
				$minigame->{ammo} = $self->value($section, "minigame_$i:ammo");		
				my $count = $self->value($section, "minigame_$i:targets");
				for (my $j = 0; $j < $count; $j++) {
					push @{$minigame->{targets}}, \split(/,/, $self->value($section, "minigame_$i:target_$j"));
				}
				$minigame->{distance} = $self->value($section, "minigame_$i:distance");
				$minigame->{cur_target} = $self->value($section, "minigame_$i:cur_target");		
				$minigame->{points} = $self->value($section, "minigame_$i:points");
				$minigame->{scored} = $self->value($section, "minigame_$i:scored");		
				$minigame->{ammo_counter} = $self->value($section, "minigame_$i:ammo_counter");				
			} elsif ($minigame->{type} eq 'three_hit_training') {
				$minigame->{wpn_type} = $self->value($section, "minigame_$i:wpn_type");
				$minigame->{win} = $self->value($section, "minigame_$i:win");
				$minigame->{ammo} = $self->value($section, "minigame_$i:ammo");		
				my $count = $self->value($section, "minigame_$i:targets");
				for (my $j = 0; $j < $count; $j++) {
					push @{$minigame->{targets}}, \split(/,/, $self->value($section, "minigame_$i:target_$j"));
				}
				$minigame->{distance} = $self->value($section, "minigame_$i:distance");
				$minigame->{cur_target} = $self->value($section, "minigame_$i:cur_target");		
				$minigame->{points} = $self->value($section, "minigame_$i:points");
				$minigame->{scored} = $self->value($section, "minigame_$i:scored");		
				$minigame->{ammo_counter} = $self->value($section, "minigame_$i:ammo_counter");				
				$minigame->{target_counter} = $self->value($section, "minigame_$i:target_counter");		
				$minigame->{target_hit} = $self->value($section, "minigame_$i:target_hit");									
			} elsif ($minigame->{type} eq 'all_targets') {			
				$minigame->{wpn_type} = $self->value($section, "minigame_$i:wpn_type");
				$minigame->{win} = $self->value($section, "minigame_$i:win");
				$minigame->{ammo} = $self->value($section, "minigame_$i:ammo");		
				my $count = $self->value($section, "minigame_$i:targets");
				for (my $j = 0; $j < $count; $j++) {
					push @{$minigame->{targets}}, \split(/,/, $self->value($section, "minigame_$i:target_$j"));
				}
				$count = $self->value($section, "minigame_$i:hitted_targets");
				for (my $j = 0; $j < $count; $j++) {
					push @{$minigame->{hitted_targets}}, \split(/,/, $self->value($section, "minigame_$i:hitted_target_$j"));
				}
				$minigame->{ammo_counter} = $self->value($section, "minigame_$i:ammo_counter");
				$minigame->{time} = $self->value($section, "minigame_$i:time");		
				$minigame->{target_counter} = $self->value($section, "minigame_$i:target_counter");
				$minigame->{prev_time} = $self->value($section, "minigame_$i:prev_time");		
				$minigame->{more_targets} = $self->value($section, "minigame_$i:more_targets");				
				$minigame->{last_target} = $self->value($section, "minigame_$i:last_target");
			} elsif ($minigame->{type} eq 'count_on_time') {
				$minigame->{wpn_type} = $self->value($section, "minigame_$i:wpn_type");
				$minigame->{win} = $self->value($section, "minigame_$i:win");
				$minigame->{ammo} = $self->value($section, "minigame_$i:ammo");		
				my $count = $self->value($section, "minigame_$i:targets");
				for (my $j = 0; $j < $count; $j++) {
					push @{$minigame->{targets}}, \split(/,/, $self->value($section, "minigame_$i:target_$j"));
				}
				$minigame->{distance} = $self->value($section, "minigame_$i:distance");
				$minigame->{cur_target} = $self->value($section, "minigame_$i:cur_target");		
				$minigame->{points} = $self->value($section, "minigame_$i:points");
				$minigame->{ammo_counter} = $self->value($section, "minigame_$i:ammo_counter");		
				$minigame->{time} = $self->value($section, "minigame_$i:time");				
				$minigame->{prev_time} = $self->value($section, "minigame_$i:prev_time");
			} elsif ($minigame->{type} eq 'ten_targets') {
				$minigame->{wpn_type} = $self->value($section, "minigame_$i:wpn_type");
				$minigame->{win} = $self->value($section, "minigame_$i:win");
				$minigame->{ammo} = $self->value($section, "minigame_$i:ammo");		
				my $count = $self->value($section, "minigame_$i:targets");
				for (my $j = 0; $j < $count; $j++) {
					push @{$minigame->{targets}}, \split(/,/, $self->value($section, "minigame_$i:target_$j"));
				}
				$minigame->{distance} = $self->value($section, "minigame_$i:distance");
				$minigame->{cur_target} = $self->value($section, "minigame_$i:cur_target");		
				$minigame->{points} = $self->value($section, "minigame_$i:points");
				$minigame->{scored} = $self->value($section, "minigame_$i:scored");
				$minigame->{ammo_counter} = $self->value($section, "minigame_$i:ammo_counter");		
				$minigame->{time} = $self->value($section, "minigame_$i:time");				
				$minigame->{prev_time} = $self->value($section, "minigame_$i:prev_time");	
			} elsif ($minigame->{type} eq 'two_seconds_standing') {
				$minigame->{wpn_type} = $self->value($section, "minigame_$i:wpn_type");
				$minigame->{win} = $self->value($section, "minigame_$i:win");
				$minigame->{ammo} = $self->value($section, "minigame_$i:ammo");		
				my $count = $self->value($section, "minigame_$i:targets");
				for (my $j = 0; $j < $count; $j++) {
					push @{$minigame->{targets}}, \split(/,/, $self->value($section, "minigame_$i:target_$j"));
				}
				$minigame->{distance} = $self->value($section, "minigame_$i:distance");
				$minigame->{cur_target} = $self->value($section, "minigame_$i:cur_target");		
				$minigame->{points} = $self->value($section, "minigame_$i:points");
				$minigame->{ammo_counter} = $self->value($section, "minigame_$i:ammo_counter");		
				$minigame->{time} = $self->value($section, "minigame_$i:time");				
				$minigame->{prev_time} = $self->value($section, "minigame_$i:prev_time");		
			}
		}
		push @{$container->{$p->{name}}}, $minigame;
	}
}

#various
sub comp_arrays {
	my $container = shift;
	my ($prop) = @_;
	return 0 if $#{$container->{$prop->{name}}} != $#{$prop->{default}};
	my ($i, $j) = (0, 0);
	foreach (@{$container->{$prop->{name}}}) {
		$j++;
		$i++ if abs($_ - $prop->{default}[$i]) < 0.0001;
		return 0 if $i != $j;
	}
	return 1;
}
sub value {
	my $self = shift;
	my ($section, $name) = @_;
	fail("$section is undefined") unless defined $self->{sections_hash}{$section};
	return $self->{sections_hash}{$section}{$name};
}
sub section_exists {return defined $_[0]->{sections_hash}{$_[1]};}
sub line_count {
	my $self = shift;
	my ($section) = @_;
	fail("$section is undefined") unless defined $self->{sections_hash}{$section};
	my $count = 0;
	foreach (keys %{$self->{sections_hash}{$section}}) {
		$count++;
	}
	return $count;	
}
sub section_safe {
	my $self = shift;
	my ($section) = @_;
	fail("$section is undefined") unless defined $self->{sections_hash}{$section};
	return $self->{sections_hash}{$section};	
}
sub section {return $_[0]->{sections_hash}{$_[1]}};
1;