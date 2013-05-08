tp = trusas_plugins
ts_cursor = new TrusasCursor()
extras = []
extras.push tp.signal_plotter
	typefilter: (type) ->
		type._subtype == 'vnd.trusas.location'
	cursor: ts_cursor
	axis: '_ts'
	field: 'speed'
	transform: (x) -> x*3.6
,
	xlabel: "Time (s)"
	ylabel: "Speed (km/h)"

extras.push tp.signal_plotter
	typefilter: (type) ->
		type._subtype == 'vnd.trusas.location'
	cursor: ts_cursor
	axis: '_ts'
	field: 'elevation'
,
	xlabel: "Time"
	ylabel: "Elevation (m)"
	
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
		ts_cursor.$.trigger "axisRangeChange", [ts_cursor.getAxisRange()]
		$("#trusas-loadingscreen").fadeOut()
