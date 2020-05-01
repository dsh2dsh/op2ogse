function element_0(shader, t_base, t_second, t_detail)
	shader:begin("fxaa_luma", "fxaa_luma")
		:fog(false)
		:zb(false, false)
	shader:dx10texture("s_base0", "$user$generic0")
end

function element_1(shader, t_base, t_second, t_detail)
	shader:begin("fxaa_main", "fxaa_main")
		:fog(false)
		:zb(false, false)
	shader:dx10texture("s_base0", "$user$generic1")
	shader:dx10sampler("smp_rtlinear")
end
