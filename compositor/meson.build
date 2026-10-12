project(
	'ultimit',
	'c',
	version: '0.1.0',
	license: 'MIT',
	meson_version: '>=1.3',
	default_options: ['c_std=c11', 'warning_level=2', 'werror=false'],
)

add_project_arguments(
	'-DWLR_USE_UNSTABLE',
	'-D_POSIX_C_SOURCE=200809L',
	'-Wno-unused-parameter',
	'-Wno-missing-field-initializers',
	language: 'c',
)

wayland_server = dependency('wayland-server')
wayland_protocols = dependency('wayland-protocols')
wlroots = dependency('wlroots-0.19', version: ['>=0.19.0', '<0.20.0'])
scenefx = dependency('scenefx-0.4')
xkbcommon = dependency('xkbcommon')
libinput = dependency('libinput')
xcb = dependency('xcb')
libdrm = dependency('libdrm').partial_dependency(compile_args: true, includes: true)
cairo = dependency('cairo')
pixman = dependency('pixman-1')
pangocairo = dependency('pangocairo')

wayland_scanner = find_program(
	dependency('wayland-scanner', native: true).get_variable('wayland_scanner'),
	native: true,
)
wp_dir = wayland_protocols.get_variable('pkgdatadir')

protocols = [
	wp_dir / 'stable/xdg-shell/xdg-shell.xml',
	wp_dir / 'staging/tearing-control/tearing-control-v1.xml',
	wp_dir / 'staging/cursor-shape/cursor-shape-v1.xml',
	wp_dir / 'unstable/pointer-constraints/pointer-constraints-unstable-v1.xml',
	wp_dir / 'unstable/tablet/tablet-unstable-v2.xml',
	wp_dir / 'staging/ext-foreign-toplevel-list/ext-foreign-toplevel-list-v1.xml',
	wp_dir / 'staging/ext-image-capture-source/ext-image-capture-source-v1.xml',
	wp_dir / 'staging/ext-image-copy-capture/ext-image-copy-capture-v1.xml',
	'protocols/wlr-layer-shell-unstable-v1.xml',
	'protocols/wlr-output-management-unstable-v1.xml',
]

protocol_headers = []
foreach xml : protocols
	protocol_headers += custom_target(
		xml.underscorify() + '_server_h',
		input: xml,
		output: '@BASENAME@-protocol.h',
		command: [wayland_scanner, 'server-header', '@INPUT@', '@OUTPUT@'],
	)
endforeach

# wlroots 0.19 has no foreign-toplevel capture source manager, so capture.c
# implements it and needs the interface tables for the protocols involved.
protocol_sources = []
foreach xml : [
	wp_dir / 'staging/ext-foreign-toplevel-list/ext-foreign-toplevel-list-v1.xml',
	wp_dir / 'staging/ext-image-capture-source/ext-image-capture-source-v1.xml',
]
	protocol_sources += custom_target(
		xml.underscorify() + '_server_c',
		input: xml,
		output: '@BASENAME@-protocol.c',
		command: [wayland_scanner, 'private-code', '@INPUT@', '@OUTPUT@'],
	)
endforeach

# Ubuntu's wlroots is linked with -Bsymbolic-functions, so its scene helpers
# would never call SceneFX's overrides. Ultimit uses a wlroots built without
# it (scripts/build-deps.sh); point the runtime linker at that copy.
deps_libdir = wlroots.get_variable(pkgconfig: 'libdir')

executable(
	'ultimit',
	[
		'src/main.c',
		'src/output.c',
		'src/input.c',
		'src/view.c',
		'src/decoration.c',
		'src/anim.c',
		'src/ipc.c',
		'src/lock.c',
		'src/config.c',
		'src/xdg.c',
		'src/xwayland.c',
		'src/layer.c',
		'src/json.c',
		'src/keys.c',
		'src/alttab.c',
		'src/capture.c',
		protocol_headers,
		protocol_sources,
	],
	dependencies: [
		# scenefx must precede wlroots: it overrides the wlr_scene_* symbols.
		scenefx, wayland_server, wlroots, xkbcommon, xcb, libdrm, pixman, cairo, pangocairo, libinput,
	],
	build_rpath: deps_libdir,
	install_rpath: deps_libdir,
	install: true,
)

# Test-only client for window/output capture (scripts/test/*_capture.sh).
protocol_client = []
foreach xml : [
	wp_dir / 'staging/ext-foreign-toplevel-list/ext-foreign-toplevel-list-v1.xml',
	wp_dir / 'staging/ext-image-capture-source/ext-image-capture-source-v1.xml',
	wp_dir / 'staging/ext-image-copy-capture/ext-image-copy-capture-v1.xml',
]
	protocol_client += custom_target(
		xml.underscorify() + '_client_h',
		input: xml,
		output: '@BASENAME@-client-protocol.h',
		command: [wayland_scanner, 'client-header', '@INPUT@', '@OUTPUT@'],
	)
	protocol_client += custom_target(
		xml.underscorify() + '_client_c',
		input: xml,
		output: '@BASENAME@-client-protocol.c',
		command: [wayland_scanner, 'private-code', '@INPUT@', '@OUTPUT@'],
	)
endforeach

executable(
	'ul-capture-probe',
	['test/ul-capture-probe.c', protocol_client],
	dependencies: [dependency('wayland-client')],
	install: false,
)
