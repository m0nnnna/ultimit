# Shell: layer-shell surfaces and the area they leave for windows.

scenario_shell_up() {
	assert_json "layer('ultimit-wallpaper') and layer('ultimit-wallpaper')['mapped']" "wallpaper layer mapped"
	assert_json "layer('ultimit-rail') and layer('ultimit-rail')['exclusive_zone']==84" "rail exclusive zone is 84"
	assert_json "layer('ultimit-topbar') and layer('ultimit-topbar')['exclusive_zone']==32" "top bar exclusive zone is 32"
	assert_json "not layer('ultimit-boot')" "boot splash gone"
	assert_json "layer('ultimit-rail')['box']['x']==0 and layer('ultimit-rail')['box']['width']==84" "rail docked left, 84 wide"
	assert_json "layer('ultimit-topbar')['box']['y']==0 and layer('ultimit-topbar')['box']['width']==full['width']" "top bar docked at the top, full width"
	assert_json "not layer('ultimit-ticker') and not layer('ultimit-status')" "no bottom strip, no desktop clock layer"
	# usable area = output minus the bar (top, 32) and the rail (left, 84)
	assert_json "box(usable)==(84, 32, full['width']-84, full['height']-32)" "usable area excludes rail and top bar"
	assert_eq "$(sj "len(s['outputs'])")" 1 "one output"
}
