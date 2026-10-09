# Shell: layer-shell surfaces and the area they leave for windows.

scenario_shell_up() {
	assert_json "layer('ultimit-wallpaper') and layer('ultimit-wallpaper')['mapped']" "wallpaper layer mapped"
	assert_json "layer('ultimit-status') and layer('ultimit-status')['mapped']" "status layer mapped"
	assert_json "layer('ultimit-rail') and layer('ultimit-rail')['exclusive_zone']==84" "rail exclusive zone is 84"
	assert_json "layer('ultimit-ticker') and layer('ultimit-ticker')['exclusive_zone']==26" "ticker exclusive zone is 26"
	assert_json "not layer('ultimit-boot')" "boot splash gone"
	assert_json "layer('ultimit-rail')['box']['x']==0 and layer('ultimit-rail')['box']['width']==84" "rail docked left, 84 wide"
	assert_json "layer('ultimit-ticker')['box']['y']+layer('ultimit-ticker')['box']['height']==full['height']" "ticker docked at the bottom"
	# usable area = output minus rail (left, 84) and ticker (bottom, 26)
	assert_json "box(usable)==(84, 0, full['width']-84, full['height']-26)" "usable area excludes rail and ticker"
	assert_eq "$(sj "len(s['outputs'])")" 1 "one output"
}
