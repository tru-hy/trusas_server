# TODO: Lots of copypaste going on, create
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

# TODO: Refactor the widget and the plot to be separate
class SignalPlotWidget
	constructor: (parent, data, opts) ->
		@$el = $("""<div class="trusas-signal"></div>""").appendTo(parent)
		@el = @$el.get(0)
		@opts = opts
		@opts.showLabelsOnHighlight ?= false
		
		@crosshair = $('<div style="position: absolute; width: 1px; height: 100%; top: 0; background-color: rgba(0,0,0,0.5); pointer-events: none"></div>').get(0)
		parent.append @crosshair
		@crosshair_pos = undefined

		if @opts.drawCallback?
			cb = @opts.drawCallback
			@opts.drawCallback = (args...) =>
				@_updateCrosshair()
				cb(args...)
		else
			@opts.drawCallback = @_updateCrosshair

		@graph = new Dygraph @el, data, @opts
		
		@_updateCrosshair()
		

	
	_updateCrosshair: =>
		if not @crosshair_pos?
			@crosshair.style.visibility = 'hidden'
			return
		@crosshair.style.left = @graph.toDomXCoord(@crosshair_pos) + "px"
		@crosshair.style.visibility = 'visible'
	
	setCrosshairPos: (pos) =>
		@crosshair_pos = pos
		@_updateCrosshair()
		
class SignalPlotWidgetFactory
	@Handler: (opts, plotopts={}) => (ctrl, register, param) =>
		return if not opts.typefilter(param.type)
		new @ opts, plotopts, ctrl, register, param

	constructor: (@opts, @plotopts, @ctrl, @onCreated, @param) ->
		@param.getcontainer
			width: 5
			height: 1
			callback: @_onParent
	
	_onParent: (@parent) =>
		#getJsonStream @param.uri, @_onData
		@ctrl.data.getJsonStreamTable @param.uri, @_onData
	
	_onData: (data) =>
		min_dt = 1.0/(@opts.max_frequency ? 5)
		transform = @opts.transform ? (x) -> x
		
		d = data.rows @opts.axis, @opts.field
		row[1] = transform row[1] for row in d
			
		if d.length == 0
			# TODO: We could do this another way around,
			#	or even more nicely with promises
			$(@parent).remove()
			@onCreated undefined
			return
		@data = d
		@_createAndConnect()
	
	_createAndConnect: ->

		@plotopts.drawCallback ?= (graph, is_initial) =>
			grng = graph.xAxisRange()
			crng = @opts.cursor.getActiveRange()
			if grng[0] == crng[0] and grng[0] == crng[0]
				return
			@opts.cursor.setActiveRange(grng)
		
		@plotopts.highlightCallback ?= (event, x, points, row, seriesName) =>
			@opts.cursor.setHoverPosition x
		@plotopts.unhighlightCallback ?= =>
			@opts.cursor.setHoverPosition undefined

		@plotopts.clickCallback ?= (ev, x, points) =>
			@opts.cursor.setActivePosition x

		widget = new SignalPlotWidget @parent, @data, @plotopts
		@opts.cursor.$.on "axisRangeChange", dcall (ev, range) =>
			# TODO: This should be configurable!
			opts = axes: x: axisLabelFormatter: (v) -> v - range[0]
			widget.graph.updateOptions opts

		@opts.cursor.$.on "activeRangeChange", dcall (ev, range) =>
			opts = dateWindow: range
			widget.graph.updateOptions opts

		@opts.cursor.$.on "activePositionChange", (ev, pos) =>
			widget.setCrosshairPos pos
		
		@opts.cursor.accommodateAxisRange @data[0][0], @data[@data.length-1][0]
		# A stupid hack around the seemingly stupid
		# behavior of resize not triggering when something hacky
		# like gridster (implicitly) resizes the container
		# TODO: Make this the UI's problem to send
		#	the resize-event
		$parent = $(@parent)
		resize_to_parent = ->
			[w, h] = [$parent.width(), $parent.height()]
			if w != widget.graph.width_ or h != widget.graph.height_
				widget.graph.resize(w, h)
		
		resize_poll_time = 300
		(=>
			resize_to_parent()
			setTimeout arguments.callee, resize_poll_time
		)()
		
		@onCreated @el

tp.signal_plotter = SignalPlotWidgetFactory.Handler

# TODO: Refactor the widget and the tracks
class MapWidget
	constructor: (parent, route, opts) ->
		$parent = @parent
		html = """<div style="" width="100%" height="100%" class="trusas-map"></div>"""
		$parent = $(parent)
		$parent.html(html)
		$el = $parent.children().first()
		el = $el[0]
		
		@map = L.map(el)
		# TODO: Make configurable
		L.tileLayer(
			'http://tiles.kartat.kapsi.fi/ortokuva/{z}/{x}/{y}.jpg',
			{ maxZoom: 19 }
			).addTo(@map)
			
		L.tileLayer(
			'http://a3.acetate.geoiq.com/tiles/acetate-roads/{z}/{x}/{y}.png',
			{ opacity: 0.8 }
			).addTo(@map)
		
		# Leaflet mangles this internally!
		route_copy = (r[..] for r in route)
		fullpath = L.polyline(route_copy,
			weight: 2
			color: "blue").addTo(@map)
	

		@activePath = L.polyline(route_copy,
			color: "red",
			weight: 4).addTo @map
		
		@activeCursor = L.marker([0, 0]).addTo(@map)

		@hoverCursor = L.circleMarker([0, 0], radius: 5).addTo(@map)
		
		# TODO: Leaflet has some problems with the initial zoom
		#	find a nicer way
		(=>
			@map.fitBounds @activePath.getBounds()
			if @map.getZoom() != 0
				$(@).trigger "widgetLoaded"
				return
			setTimeout arguments.callee, 100
		)()
		

class CoordinateRoute
	constructor: (@axis, @lat, @lon, @bearing, @elevation, @geod=GeographicLib.Geodesic.WGS84) ->
		@subpath = rangepath(@axis, @lat, @lon)
		@coords = ([@lat[i], @lon[i]] for i in [0..@axis.length-1])
		# TODO: This should probably be done in projected space!
		#@coord_spline = numeric.spline @axis, @coords
		#@delta_spline = @coord_spline.diff()
		#@bearingAt = (c) =>
		#	[x, y] = @delta_spline.at c
		#	return (Math.atan2 y, x)*(180/Math.PI)
		if @bearing?
			@bearingAt = deg_interp @axis, @bearing

		@coordAt = coord_interp(@axis, @lat, @lon)
		
		if @elevation?
			@elevationAt = interp1d(@axis, @elevation)
	
	getContainedSlice: (bounds) =>
		# TODO: Find a proper library for this
		# TODO: Take distances in constructor so we can use them
		# TODO: Interpolate edges
		contained = []
		for i in [0..@coords.length-1]
			continue if not bounds.contains @coords[i]
			contained.push i
		
		current = []
		continuous = [current]
		for i in [0..contained.length-1]
			if contained[i+1] - contained[i] == 1
				current.push contained[i]
				continue
			current = []
			continuous.push current
		
		maxlen = 0
		winner = []
		for span in continuous
			if span.length > maxlen
				winner = span
				maxlen = span.length
		
		return [winner[0], winner[winner.length - 1]]
	
		


class MapWidgetFactory
	@Handler: (opts, plotopts={}) => (ctrl, register, param) =>
		return if not opts.typefilter(param.type)
		new @ opts, plotopts, ctrl, register, param

	constructor: (@opts, @plotopts, @ctrl, @onCreated, @param) ->
		@param.getcontainer
			width: 4
			height: 4
			callback: @_onParent
	
	_onParent: (@parent) =>
		#getJsonStream @param.uri, @_onData
		@ctrl.data.getJsonStreamTable @param.uri, @_onData
	
	_onData: (data) =>
		cols = data.columns @opts.axis,
			@opts.lat_field ? "latitude",
			@opts.lon_field ? "longitude"
		
		if cols[0].length == 0
			# TODO: We could do this another way around,
			#	or even more nicely with promises
			$(@parent).remove()
			@onCreated undefined
			return
		
		@route = new CoordinateRoute(cols[0], cols[1], cols[2])
	
		@_createAndConnect()
	
	_createAndConnect: ->
		widget = new MapWidget @parent, @route.coords, @plotopts
		$el = $(@el)

		# A stupid hack around the seemingly stupid
		# behavior of resize not triggering when something hacky
		# like gridster (implicitly) resizes the container
		resize_poll_time = 300
		$parent = $(@parent)
		setTimeout =>
			ms = widget.map.getSize()
			if $parent.width() != ms.x or $parent.height() != ms.y
				widget.map.invalidateSize()
			setTimeout arguments.callee, resize_poll_time
			, 0
		
		# TODO: Find something more general
		#	and async-robust for this!
		ignoreRange = false
		fitRange = (ev) =>
			range = @opts.cursor.getActiveRange()
			subroute = @route.subpath range...
			widget.activePath.setLatLngs(subroute)
			return if ignoreRange
			widget.map.fitBounds widget.activePath.getBounds()
			

		@opts.cursor.$.on "activeRangeChange", dcall fitRange
		@opts.cursor.$.on "activePositionChange", (ev, pos) =>
			latlon = @route.coordAt pos
			widget.activeCursor.setLatLng latlon

		@opts.cursor.$.on "hoverPositionChange", (ev, position) =>
			latlon = @route.coordAt position
			if isNaN latlon[0]
				# FIXME: A hack to hide the marker
				latlon = [0, 0]
			widget.hoverCursor.setLatLng latlon
		
		updateRange = =>
			bounds = widget.map.getBounds()
			slice = @route.getContainedSlice bounds
			range = [@route.axis[slice[0]], @route.axis[slice[1]]]
			ignoreRange = true
			#@opts.cursor.setActivePosition (range[1]+range[0])/2
			@opts.cursor.setActiveRange range
			ignoreRange = false
		
		$(widget).on "widgetLoaded", ->
			widget.map.on "drag", updateRange
			widget.map.on "zoomend", updateRange

		@onCreated @el
		
		
		
tp.map = MapWidgetFactory.Handler

class StreetViewFactory
	@Handler: (opts, plotopts={}) => (ctrl, register, param) =>
		return if not opts.typefilter(param.type)
		new @ opts, plotopts, ctrl, register, param

	constructor: (@opts, @plotopts, @ctrl, @onCreated, @param) ->
		@param.getcontainer
			width: 5
			height: 2
			callback: @_onParent
	
	_onParent: (@parent) =>
		#getJsonStream @param.uri, @_onData
		@ctrl.data.getJsonStreamTable @param.uri, @_onData
	
	_onData: (data) =>
		cols = data.columns @opts.axis,
			@opts.lat_field ? "latitude",
			@opts.lon_field ? "longitude"
		
		if cols[0].length == 0
			# TODO: We could do this another way around,
			#	or even more nicely with promises
			$(@parent).remove()
			@onCreated undefined
			return
		
		@route = new CoordinateRoute cols...
	
		@_createAndConnect()
	
	_createAndConnect: ->
		@$el = $("""<div class="widget trusas-streetview"></div>""").appendTo(@parent)
		@el = @$el.get(0)

		$el = $(@el)
		
		widget = new google.maps.StreetViewPanorama @el

		widget.setVisible true

		@opts.cursor.$.on "activePositionChange", (ev, pos) =>
			coords = @route.coordAt pos
			bearing = @route.bearingAt pos
			pos = new google.maps.LatLng coords...
			widget.setPosition pos
			widget.setPov heading: bearing, pitch: 0
			widget.setVisible true
		
		@onCreated @el

tp.streetview = StreetViewFactory.Handler

class CesiumFactory
	@Handler: (opts, plotopts={}) => (ctrl, register, param) =>
		return if not opts.typefilter(param.type)
		new @ opts, plotopts, ctrl, register, param

	constructor: (@opts, @plotopts, @ctrl, @onCreated, @param) ->
		@param.getcontainer
			width: 5
			height: 4
			callback: @_onParent
	
	_onParent: (@parent) =>
		#getJsonStream @param.uri, @_onData
		@ctrl.data.getJsonStreamTable @param.uri, @_onData
	
	_onData: (data) =>
		cols = data.columns @opts.axis,
			@opts.lat_field ? "latitude",
			@opts.lon_field ? "longitude",
			@opts.bearing_field ? "bearing",
			@opts.elevation_field ? "elevation"
		
		if cols[0].length == 0
			# TODO: We could do this another way around,
			#	or even more nicely with promises
			$(@parent).remove()
			@onCreated undefined
			return
		
		@route = new CoordinateRoute cols...
	
		@_createAndConnect()
	
	_createAndConnect: ->
		@$el = $("""<div class="widget trusas-cesium"></div>""").appendTo(@parent)
		@el = @$el.get(0)

		$el = $(@el)

		bluemarble = new Cesium.TileMapServiceImageryProvider
			url: 'http://cesium.agi.com/blackmarble'
			maximumLevel : 8
		
		osm = new Cesium.OpenStreetMapImageryProvider
			url: 'http://tile.openstreetmap.org/'
			maximumLevel: 12
			
		class MinzoomlevelDiscard
			constructor: (@minlevel) ->
				
			shouldDiscardImage: (img) =>
				src = img.src
				parts = src.split("/")
				z = parseInt parts[parts.length - 3]
				discard = (z < @minlevel)
				#return z < @minlevel
				return discard

			isReady: -> true
		
		openaerial = new Cesium.OpenStreetMapImageryProvider
			url: "http://otile1.mqcdn.com/tiles/1.0.0/sat/"
			maximumLevel: 11
		
		ortopic = new Cesium.OpenStreetMapImageryProvider
			url: 'http://tiles.kartat.kapsi.fi/ortokuva/'
			maximumLevel: 19
			tileDiscardPolicy: new MinzoomlevelDiscard 13

			
		###
		terrain = new Cesium.CesiumTerrainProvider
			url: "http://cesium.agi.com/smallterrain/"
		terrain = new Cesium.VRTheWorldTerrainProvider
			url : 'http://www.vr-theworld.com/vr-theworld/tiles1.0.0/73/'

		terrain = new Cesium.ArcGisImageServerTerrainProvider
			url :'http://elevation.arcgisonline.com/ArcGIS/rest/services/WorldElevation/DTMEllipsoidal/ImageServer'
			token: "e7DdYy9h9Ry2aq19iaddyq63YadpSwWw7fTpMGky6RmpAT_jX4YbH4qTeR5fxJRzTJ63I0xhJuaCZZNjIReeZQ"
		###
		
		###
		ortopic = new Cesium.WebMapServiceImageryProvider
			url: "http://tiles.kartat.kapsi.fi/ortokuva?"
			layers: "ortokuva"
			parameters:
				format: "image/png"
			tileDiscardPolicy: new OrtopicDiscard
		###

		widget = new Cesium.CesiumWidget @el

		layers = widget.centralBody.getImageryLayers()
		layers.removeAll()
		
		#layers.addImageryProvider osm
		#layers.addImageryProvider openaerial
		layers.addImageryProvider ortopic
		#layers.add bluemarble

			#terrainProvider: terrain
		# TODO: Seems to resize only by scaling
		###
		console.log widget.container
		(=>
			console.log widget.container.clientWidth
			setTimeout arguments.callee, 100
		)()
		###

		cam = widget.scene.getCamera()
		controller = cam.controller
		pos = @route.coords[0]
		elev = @route.elevation[0]

		cameraHeight = @opts.cameraHeight ? 40.0
		cameraBehind = @opts.cameraBehind ? 60.0
		
		geod = GeographicLib.Geodesic.WGS84
		ellipsoid = Cesium.Ellipsoid.WGS84
		pos = Cesium.Cartographic.fromDegrees pos[1], pos[0], elev+cameraHeight

		

		degToCartesian = (lon, lat, height) ->
			cart = Cesium.Cartographic.fromDegrees lon, lat, height
			return ellipsoid.cartographicToCartesian cart
		
		polylines = new Cesium.PolylineCollection()
		arrowMaterial = Cesium.Material.fromType undefined, Cesium.Material.PolylineArrowType
		positionmarker = polylines.add()

		markerLength = @opts.markerLength ? 10.0
		markerWidth = @opts.markerWidth ? 40.0

		@opts.cursor.$.on "activePositionChange", (ev, pos) =>
			# Couldn't find geodesics in Cesium
			[lat, lon] = @route.coordAt pos
			bearing = @route.bearingAt pos
			origin = geod.Direct lat, lon, bearing, -cameraBehind
			
			#elev = @route.elevationAt pos
			eye = degToCartesian origin.lon2, origin.lat2, cameraHeight
			target = degToCartesian lon, lat, 0.0
			up = ellipsoid.geodeticSurfaceNormal eye

			controller.lookAt eye, target, up

			marker_start = geod.Direct lat, lon, bearing - 15, -markerLength/2.0
			marker_end = geod.Direct lat, lon, bearing + 15, -markerLength/2.0
			marker_mid = geod.Direct lat, lon, bearing, + markerLength/2.0
			marker_start = degToCartesian(marker_start.lon2, marker_start.lat2, 0)
			marker_mid = degToCartesian(marker_mid.lon2, marker_mid.lat2, 0)
			marker_end = degToCartesian(marker_end.lon2, marker_end.lat2, 0)
			
			positionmarker.setPositions [marker_start, marker_mid, marker_end]

			#pos = Cesium.Cartographic.fromDegrees latlon[1], latlon[0], cameraHeight
			#controller.setPositionCartographic pos
			#controller.lookUp 45

		
		
	
		routeline = polylines.add()
		
		newaxis = []
		v = @route.axis[0]
		end = @route.axis[@route.axis.length - 1]
		while v < end
			newaxis.push v
			v =  v + 0.5

		coords = (@route.coordAt a for a in newaxis)
		mangled = (Cesium.Cartographic.fromDegrees(p[1], p[0], 0) for p in coords)
		cart_route = ellipsoid.cartographicArrayToCartesianArray(mangled)
		routeline.setPositions cart_route
		widget.scene.getPrimitives().add polylines
		
		@onCreated @el

tp.cesium = CesiumFactory.Handler

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
		if new_x < x[0]
			return NaN
		prev_i = searchsorted(new_x, x)
		ratio = (new_x - x[prev_i])/(x[prev_i+1] - x[prev_i])
		return y[prev_i]*(1 - ratio) + y[prev_i + 1]*(ratio)
	return interp

coord_interp = (dist, lat, lon) ->
	lati = interp1d(dist, lat)
	loni = interp1d(dist, lon)
	interp = (new_x) ->
		return [lati(new_x), loni(new_x)]
	return interp

deg_interp = (axis, angles) ->
	units = ([Math.sin(a*(Math.PI/180)), Math.cos(a*(Math.PI/180))] for a in angles)
	#spline = numeric.spline axis, units
	xi = interp1d axis, (Math.sin a*(Math.PI/180) for a in angles)
	yi = interp1d axis, (Math.cos a*(Math.PI/180) for a in angles)
	interp = (new_a) ->
		x = xi(new_a)
		y = yi(new_a)
		#res = spline.at new_a
		#[x, y] = res
		angle = Math.atan2 x, y
		angle = angle*(180/Math.PI)
		return angle
	return interp


rangepath = (dists, lats, lons) ->
	coord_i = coord_interp(dists, lats, lons)
	get_path = (start, end) ->
		if start < dists[0]
			start = dists[0]

		if end > dists[-1]
			end = dists[-1]
		
		first = searchsorted(start, dists) + 1
		last = searchsorted(end, dists)
		start = coord_i(start)
		end = coord_i(end)
		
		plats = [start[0]].concat(lats[first..last]).concat([end[0]])
		plons = [start[1]].concat(lons[first..last]).concat([end[1]])
		coords = ([plats[i], plons[i]] for i in [0..(plats.length-1)])
		# HACK!!! FIX THE SEARCHSORTED!!
		last_i = coords.length - 1
		if isNaN(coords[last_i][0])
			coords[last_i] = [lats[lats.length - 1], lons[lons.length - 1]]
		return coords
	return get_path
