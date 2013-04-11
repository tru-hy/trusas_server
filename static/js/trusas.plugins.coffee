# TODO: Lot's of copypaste going on, create
#	a generic helper for common plugin cases

@trusas_plugins = {}
tp = @trusas_plugins
tp.defaults = []

class VideoWidget
	@Load: (controller, register, param) =>
		{uri, type, getcontainer} = param
		return if type._type != 'video'
		if not resources
			resources = 'resources.json'
		return if not timemap_uri = type.timemap
		
		register_widget = (param, timemap, parent) =>
			try
				widget = new @ uri, timemap, type: type
			catch e
				register param, WidgetError(@, uri, type, e)
				return
			$parent = $(parent)
			$parent.html(widget.element_html())
			$el = $parent.children().first()
			el = $el[0]
			widget.element = el

			register param, el,
				calls:
					play: -> el.play()
					pause: -> el.pause()
					getCurrentTime: widget.getCurrentTime
					setCurrentTime: widget.setCurrentTime
					getDuration: -> el.duration
					getStartTime: widget.getStartTime
				events:
					timeupdate: el
					durationchange: el
					canplay: el
		
		getcontainer
			width: 5
			height: 3
			callback: (parent) =>
				getJsonStream timemap_uri, (timemap) =>
					register_widget param, timemap, parent
			
		return true
		

	constructor: (@uri, timemap, @options) ->
		ts = []
		sts = []
		for row in timemap
				ts.push row[0]['ts']
				sts.push row[1]['stream_ts']
		@stream_to_global = interp1d sts, ts
		@global_to_stream = interp1d ts, sts
		
	element_html: =>
		# Hacking around http://code.google.com/p/chromium/issues/detail?id=31014
		# TODO: Breaks if uri has a query string!
		# TODO: Forces properly behaving browsers to download duplicate stuff
		#	unnecessarily
		hackuri = @uri + "?chromiumhack=#{Math.random()}"
		"""<video preload><source src="#{hackuri}"></video>"""

		
	
	getCurrentTime: =>
		@stream_to_global @element.currentTime

	setCurrentTime: (ts) =>
		@element.currentTime = @global_to_stream ts

	getStartTime: => @stream_to_global 0.0
	
tp.video = VideoWidget.Load
tp.defaults.push tp.video

tp.signal_plotter = (opts) ->
	handler = (ctrl, register, param) ->
		{uri, type, getcontainer} = param
		return if not opts.typefilter(type)
		
		create_widget = (param, data, parent) ->
			transform = opts.transform ? (y) -> y
			d = []
			for row in data
				d.push
					x: row[0].ts
					y: transform(row[1][opts.field])
			
			html = """<div width="100%" height="100%" class="trusas-signal"></div>"""
			$parent = $(parent)
			$parent.html(html)
			$el = $parent.children().first()
			el = $el[0]
			
			graph = new Rickshaw.Graph(
				element: el
				series: [
					{color: opts.color ? 'steelblue', data: d}
					],
				renderer: opts.renderer ? 'line'
			)
			
			x_axis = new Rickshaw.Graph.Axis.Time(graph: graph)
			y_axis = new Rickshaw.Graph.Axis.Y(graph: graph)
			
			graph.onUpdate(-> rendered = true)
			render = ->
				p = $parent
				graph.configure
					width: p.width()
					height: p.height()
				graph.render()
			
			# A stupid hack around the seemingly stupid
			# behavior of resize not triggering when something hacky
			# like gridster (implicitly) resizes the container
			resize_poll_time = 300
			(->
				if $el.width() != graph.width or $el.height() != graph.height
					render()
				setTimeout arguments.callee, resize_poll_time
			)()
				

			$parent.load -> render

			$(ctrl).on "timeupdate", ->
				time = ctrl.getCurrentSessionTime()
				graph.window.xMin = time-60
				graph.window.xMax = time
				graph.update()

		
			register(param, el)
		
		getcontainer
			width: 5
			height: 1
			callback: (parent) ->
				getJsonStream uri, (data) ->
					create_widget param, data, parent

		return true

tp.faster_signal_plotter = (opts) ->
	handler = (ctrl, register, param) ->
		{uri, type, getcontainer} = param
		return if not opts.typefilter(type)
		create_widget = (param, data, parent) ->
			
			$parent = $(parent)
			$el = $("""<div class="trusas-signal"></div>""").appendTo(parent)
			el = $el.get(0)
			transform = opts.transform ? (x) -> x

			min_dt = 1.0/(opts.max_frequency ? 5)
			
			prev_ts = NaN
			d = []
			for row in data
				val = row[1][opts.field]
				continue if isNaN(val)
				ts = row[0].ts

				continue if not isNaN(prev_ts) and (ts - prev_ts) < min_dt
				prev_ts = ts
				d.push [ ts, transform(row[1][opts.field])]
			
			opts.interactionModel ?= {}
			graph = new Dygraph el, d, opts
			
			# A stupid hack around the seemingly stupid
			# behavior of resize not triggering when something hacky
			# like gridster (implicitly) resizes the container
			resize_poll_time = 300
			(->
				[w, h] = [$parent.width(), $parent.height()]
				if w != graph.width_ or h != graph.height_
					graph.resize(w, h)
				setTimeout arguments.callee, resize_poll_time
			)()

			
			redraw_interval = opts.redraw_interval ? 0
			graph.redraw_pending = false
			graph.window_len = 60

			refresh_window = ->
				time = ctrl.getCurrentSessionTime()
				graph.pendingWindow = [time-graph.window_len,
						time+redraw_interval/1000.0]
				#graph.updateOptions
				#	dateWindow: [time-60, time]
				#, true

				if not graph.redraw_pending
					graph.redraw_pending = true
					setTimeout ->
						graph.updateOptions(dateWindow: graph.pendingWindow)
						graph.redraw_pending = false
						
					, redraw_interval

			$(ctrl).on "timeupdate", refresh_window
			
			# TODO: This may not be the most portable thing
			$el.on "mousewheel", (ev) ->
				ev.preventDefault()
				delta = ev.originalEvent.wheelDelta
				return if not delta
				ratio = 1 + (-delta/120.0)*0.1
				graph.window_len *= ratio
				refresh_window()
							
			register(param, el)
				
		getcontainer
				width: 5
				height: 1
				callback: (parent) ->
					getJsonStream uri, (data) ->
						create_widget param, data, parent
		return true

tp.map = (opts={}) ->
	(ctrl, register, param) ->
		{uri, type, getcontainer} = param
		return if type._subtype != 'vnd.trusas.location'
		create_widget = (param, data, parent) ->
			html = """<div style="" width="100%" height="100%" class="trusas-map"></div>"""
			$parent = $(parent)
			$parent.html(html)
			$el = $parent.children().first()
			el = $el[0]

			route = []
			route_times = []
			for d in data
				[hdr, d] = d
				route_times.push hdr.ts
				route.push [d.latitude, d.longitude]
			
			map = L.map(el)
			# TODO: Make configurable
			L.tileLayer(
				'http://tiles.kartat.kapsi.fi/ortokuva/{z}/{x}/{y}.jpg',
				{ maxZoom: 19 }
				).addTo(map)
			
			L.tileLayer(
				'http://a3.acetate.geoiq.com/tiles/acetate-roads/{z}/{x}/{y}.png',
				{ opacity: 0.8 }
				).addTo(map)

			map.route_interp = [
				interp1d(route_times, r[0] for r in route),
				interp1d(route_times, r[1] for r in route)
				]

			map.setView(route[0], 16)
			set_current_pos = (pos) ->
				map.panTo(pos)
				map.current_marker.setLatLng(pos)

			L.polyline(route, {weight: 2}).addTo(map)
			map.current_marker = L.marker(route[0])
			map.current_marker.addTo(map)

			# A stupid hack around the seemingly stupid
			# behavior of resize not triggering when something hacky
			# like gridster (implicitly) resizes the container
			resize_poll_time = 300
			setTimeout ->
				[mw, mh] = map.getSize()
				if $el.width() != mw or $el.height() != mh
					map.invalidateSize()
				setTimeout arguments.callee, resize_poll_time
			, 0
			
			$(ctrl).on "timeupdate", ->
				t = ctrl.getCurrentSessionTime()
				latlon = [map.route_interp[0](t), map.route_interp[1](t)]
				set_current_pos latlon

			register(param, el)

		
		getcontainer
				width: 3
				height: 3
				callback: (parent) ->
					getJsonStream uri, (data) ->
						create_widget param, data, parent

		return true

tp.default_map = tp.map()
tp.defaults.push tp.default_map

json_stream_to_array = (stream) ->
	json = []
	for line in stream.split '\n'
		continue if line.trim() == ''
		json.push $.parseJSON line
	return json

getJsonStream = (uri, success, opts={}) ->
  # TODO: Really stream
	opts.success = (data, args...) ->
		success json_stream_to_array(data), args...
	$.ajax uri, opts

# TODO: This is just a temporary deadlinehack,
#	make it a proper "plugin" too
tp.load_annotations = (success, opts) ->
	getJsonStream "trusas-annotations.jsons", success, opts


searchsorted = (needle, haystack, base=0) ->
	# Should really use interpolation search
	# in our cases
	len = haystack.length
	if len <= 1
		return base
	mid_i = Math.floor(len/2)
	mid_val = haystack[mid_i]
	if needle < mid_val
		return searchsorted(needle, haystack[0..mid_i-1], base)
	return searchsorted(needle, haystack[mid_i..], mid_i+base)

interp1d = (x, y) ->
	interp = (new_x) ->
		prev_i = searchsorted(new_x, x)
		ratio = (new_x - x[prev_i])/(x[prev_i+1] - x[prev_i])
		return y[prev_i]*(1 - ratio) + y[prev_i + 1]*(ratio)
	return interp

