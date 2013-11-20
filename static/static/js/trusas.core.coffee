# TODO! THE CONTROL FLOW IS VERY WEIRD!!!

@Trusas = {}

class _Lazycall
	constructor: (@func, @timeout=300) ->
		@pending = undefined
		@embargo = false

	schedule: (args...) =>
		@pending = args
		return if @embargo
		@_handle()
	
	_release_embargo: =>
		@embargo = false
		if @pending?
			@_handle @pending

	_handle: =>
		@embargo = true
		args = @pending
		@pending = undefined
		@func args...
		setTimeout @_release_embargo, @timeout
		
@dcall = (func, timeout=300) ->
	handler = new _Lazycall func, timeout
	return handler.schedule

parse_basepath = (url) ->
	i = url.lastIndexOf '/'
	if i < 0
		return ''
	return url[0..i]

@new_trusas_controller = (opts) ->
	{success, getcontainer, error, complete, resources,
	oncreated, handlers} = opts

	handlers ?= @trusas_plugins.defaults
	ctrl = new TrusasController()
	
	if not resources
		resources = 'resources/index.json'
	
	load_handlers = (complete, basepath, resources, oncreated, getcontainer) =>
		loading = []
		loaded = []
		handlers_notified = false
		completion_notified = false

		on_load_complete = ->
			complete() if complete
			ctrl._baseTime = ctrl._firstTime
			$(ctrl).trigger 'timebase'
			$(ctrl).trigger 'timeupdate'
			$(ctrl).trigger 'durationchange'


		notify_if_complete = ->
			return if completion_notified
			return if not handlers_notified
			for target in loading
				if target not in loaded
					return
			completion_notified = true
			on_load_complete()
			
		registerer = (param) => (element, {calls, events}={}) =>
			loaded.push param
			if oncreated and element
				oncreated element, param
			if calls or events
				ctrl.add_controllee calls ? {}, events ? {}

			notify_if_complete()
			
		for handler in handlers
			for uri of resources
				type = mime_parse resources[uri]
				if basepath
					access_uri = basepath + uri
				else
					access_uri = uri
				param =
					uri: access_uri, type: type, handler: handler,
					getcontainer: getcontainer,
					raw_uri: uri, basepath: basepath

				if handler ctrl, registerer(param), param
					loading.push param
		
		handlers_notified = true
		notify_if_complete()
	
	if typeof(resources) == 'string'
		basepath = parse_basepath resources
	else
		basepath = ''
	
	loader = (resources) =>
		load_handlers(complete, basepath, resources, oncreated, getcontainer)
	
	if typeof(resources) == 'string'
		$.getJSON resources, loader
	else
		loader resources
	return ctrl

class @TrusasCursorPlayer
	constructor: (@cursor, @dt=0.1, @rate=2) ->
		@looper = undefined

	isPlaying: =>
		return @looper?

	play: =>
		return if @isPlaying()
		if not @cursor.getActivePosition?
			@cursor.setActivePosition @cursor.getAxisRange()[0]
		@looper = setInterval(@_step, @dt*1000)
	
	_step: =>
		prev = @cursor.getActivePosition()
		activerange = @cursor.getActiveRange()
		lwidth = Math.max 0, prev - activerange[0]
		rwidth = Math.max 0, activerange[1] - prev

		next = prev + @dt*@rate
		totalrange = @cursor.getAxisRange()
		new_range = [
			Math.max(totalrange[0], next - lwidth)
			Math.min(totalrange[1], next + rwidth)
			]
		@cursor.setActivePosition next
		@cursor.setActiveRange new_range


	pause: =>
		clearInterval @looper
		@looper = undefined

class TrusasCursor
	constructor: ->
		@$ = $(@)
		@_axisRange = [undefined, undefined]
		@_activePosition = undefined
		@_activeRange = [undefined, undefined]
		@_hoverPosition = undefined
	
	_activeRangeDefined: ->
		@_activeRange[0]? and @_activeRange[1]?
	
	getAxisRange: => @_axisRange
	accommodateAxisRange: (min, max) =>
		changed = false
		# Weird comparisons to work with undefined
		if min? and not (min >= @_axisRange[0])
			changed = true
			@_axisRange[0] = min

		if max? and not (max <= @_axisRange[1])
			changed = true
			@_axisRange[1] = max

		return if not changed
		
		@$.trigger "axisRangeChange", [@_axisRange]
		
		if not @_activeRangeDefined()
			@$.trigger "activeRangeChange",
				[@getActiveRange()]

	
	getActivePosition: => @_activePosition
	setActivePosition: (position) =>
		@_activePosition = position
		@$.trigger "activePositionChange", [position]
	
	getActiveRange: =>
		[min, max] = @_activeRange[..]
		rng = [ min ? @_axisRange[0], max ? @_axisRange[1] ]
		return rng
	
	setActiveRange: (range) =>
		prev = @getActiveRange()
		@_activeRange = range
		new_range = @getActiveRange()
		return if (prev[0] == new_range[0]) and
			(prev[1] == new_range[1])

		@$.trigger "activeRangeChange", [new_range]
	
	getHoverPosition: => @_hoverPosition
	setHoverPosition: (position) =>
		@_hoverPosition = position
		$(@).trigger "hoverPositionChange", position

@TrusasCursor = TrusasCursor

Trusas.coords_extent = (coords) ->
	minlat = maxlat = coords[0][0]
	minlon = maxlon = coords[0][1]
	for c in coords[1..]
		if c[0] < minlat
			minlat = c[0]
		else if c[0] > maxlat
			maxlat = c[0]
		
		if c[1] < minlon
			minlon = c[1]
		else if c[1] > maxlon
			maxlon = c[1]
	
	return [[minlat, minlon], [maxlat, maxlon]]

Trusas.radians = (deg) -> deg*(Math.PI/180)


class TrusasController
	constructor: ->
		@data = new DataManager()
		@_cursors = {}

		@_controllees = []
		@_canplay = []
		@_playing = false
		@_currentTime = undefined
		@_firstTime = undefined
		@_lastTime = undefined
	
	

	add_controllee: (calls, events) =>
		c = new Controllee calls, events
		s = c.getStartTime()
		e = s + c.getDuration()
		@_firstTime = s if not (s > @_firstTime)
		@_lastTime = e if not (e < @_lastTime)
		
		$(c).bind "durationchange", =>
			e = c.getStartTime() + c.getDuration()
			@_lastTime = e if not (e <= @_lastTime)
			$(@).trigger "durationchange"
		
		$(c).on "timeupdate", =>
			t = c.getCurrentTime()
			return if @_currentTime > t
			@_currentTime = t
			
			$(@).trigger "timeupdate"

		@_controllees.push c
	
	
	play: =>
		@_playing = true
		c?.play() for c in @_controllees
		
	pause: (e) =>
		@_playing = false
		c?.pause() for c in @_controllees
	
	toSessionTime: (ts) => ts + @_firstTime

	toStreamTime: (ts) => ts - @_firstTime
			
	setCurrentTime: (ts) =>
		ts += @_firstTime
		return if isNaN ts
		@_currentTime = ts
		c?.setCurrentTime ts for c in @_controllees
		$(@).trigger "timeupdate"
	
	getCurrentTime: =>
		t = @_currentTime - @_firstTime
		return 0.0 if isNaN t
		return t
	
	getCurrentSessionTime: =>
		return @toSessionTime @getCurrentTime()

	getDuration: =>
		d = (@_lastTime - @_firstTime)
		return 0.0 if isNaN d
		return d

	isPaused: => not @_playing

class Controllee
	constructor: (calls, events) ->
		for name of calls
			@[name] = calls[name]
		
		# Struggling a bit with the scoping, so
		# let's hack it
		$this = $ @
		$this.eventmap = {}
		for name of events
			src = events[name]
			if src instanceof Array
				[src, srcevent] = src
			else
				srcevent = name

			$this.eventmap[srcevent] = name
			$(src).on srcevent, (ev) =>
				event = $this.eventmap[ev.type]
				$this.trigger event

# TODO: Find out some better library for this!
class RecordTable
	constructor: (@records) ->
	
	rows: (keys...) =>
		n = keys.length
		rows = []
		for rrow in @records
			drow = []
			for key in keys
				drow.push rrow[key] if key of rrow
			if drow.length == n
				rows.push drow
		return rows

	columns: (keys...) =>
		n = keys.length
		rng = [0..(keys.length - 1)]
		columns = ([] for i in rng)
		for row in @records
			vals = []
			for i in rng
				if not row.hasOwnProperty keys[i]
					break
				vals.push row[keys[i]]
			continue if vals.length != n
			columns[i].push vals[i] for i in rng

		return columns
		

class DataManager
	constructor: ->
		# TODO: We could use Deferred or something else
		#	non-ad-hoc
		@datasets = {}
	
	getJsonStreamTable: (uri, cont) =>
		if uri of @datasets
			cont @datasets[uri]
			return
		
		getJsonStream uri, (data) =>
			@datasets[uri] = new RecordTable data
			cont @datasets[uri]

getJsonStream = (uri, success, opts={}) ->
	# TODO: Really stream
	opts.success = (data, args...) ->
		success json_stream_to_flat_array(data), args...
	opts.dataType = "text"
	$.ajax uri, opts

json_stream_to_flat_array = (stream) ->
	array = []
	for line in stream.split '\n'
		continue if line.trim() == ''
		row = $.parseJSON line
		for key of row[0]
			row[1]["_"+key] = row[0][key]
		array.push row[1]
	return array
		

class WidgetError extends Error
	constructor: (@origin, @uri, @type, @reason) ->
		super

	
mime_parse = (mime) ->
	[type, opts...] = mime.split ';'
	r = {}
	param = {}
	for opt in opts
		[name, value] = opt.split '=', 2
		name = name.trim()
		value = value.trim()
		if value
			param[name] = value if name
		else
			param[name] = true
	
	r.param = param
	[r.type, r.subtype] = (v.trim() for v in type.split '/', 2)
	return r

Trusas.searchsorted = searchsorted = (needle, haystack, base=0) ->
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
	
Trusas.interp1d = interp1d = (x, y) ->
	interp = (new_x) ->
		if new_x < x[0]
			return NaN
		prev_i = searchsorted(new_x, x)
		ratio = (new_x - x[prev_i])/(x[prev_i+1] - x[prev_i])
		return y[prev_i]*(1 - ratio) + y[prev_i + 1]*(ratio)
	return interp


Trusas.coord_interp = coord_interp = (dist, lat, lon) ->
	lati = interp1d(dist, lat)
	loni = interp1d(dist, lon)
	interp = (new_x) ->
		return [lati(new_x), loni(new_x)]
	return interp

Trusas.deg_interp = deg_interp = (axis, angles) ->
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


Trusas.rangepath = rangepath = (dists, lats, lons) ->
	coord_i = Trusas.coord_interp(dists, lats, lons)
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
