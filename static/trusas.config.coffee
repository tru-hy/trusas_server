tp = trusas_plugins
extras = []
extras.push tp.signal_plotter
	typefilter: (type) ->
		type._subtype == 'vnd.trusas.location'
	axis: '_ts',
	field: 'speed'
	transform: (x) -> x*3.6

extras.push tp.signal_plotter
	typefilter: (type) ->
		type._subtype == 'vnd.trusas.location'
	axis: '_ts',
	field: 'elevation'
	transform: (x) -> x*3.6
	
g_heading = tp.faster_signal_plotter
	typefilter: (type) ->
		type._subtype == 'vnd.trusas.tru.smarteye'
	field: 'g_est_heading'
	drawPoints: true
	strokeWidth: 0.0
extras.push g_heading

g_yaw_rate = tp.faster_signal_plotter
	typefilter: (type) ->
		type._subtype == 'vnd.trusas.sensors'
	field: 'rot_rate_z'
	drawPoints: false
extras.push g_yaw_rate

trusas_create_ui
	handlers: [].concat(tp.defaults, extras)
	uiready: ->
		$("#trusas-loadingscreen").fadeOut()
