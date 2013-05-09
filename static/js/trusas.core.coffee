# TODO! THE CONTROL FLOW IS VERY WEIRD!!!

@new_trusas_controller = (opts) ->
	{success, getcontainer, error, complete, resources,
	oncreated, handlers} = opts

	handlers ?= @trusas_plugins.defaults
	ctrl = new TrusasController()
	
	if not resources
		resources = 'resources.json'
	
	load_handlers = (complete, resources, oncreated, getcontainer) =>
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
				param =
					uri: uri, type: type, handler: handler,
					getcontainer: getcontainer

				if handler ctrl, registerer(param), param
					loading.push param
		
		handlers_notified = true
		notify_if_complete()

  
	loader = (resources) => load_handlers(complete, resources, oncreated, getcontainer)
	if typeof(resources) == 'string'
		$.getJSON resources, loader
	else
	  loader resources
	return ctrl

class @TrusasCursorPlayer
	constructor: (@cursor, @dt=0.1) ->
		@looper = undefined

	play: =>
		return if @looper
		if not @cursor.getActivePosition?
			@cursor.setActivePosition @cursor.getAxisRange()[0]
		@looper = setInterval(@_step, @dt*1000)
	
	_step: =>
		next = @cursor.getActivePosition() + @dt*2
		@cursor.setActivePosition next

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
		@_activeRange = range
		@$.trigger "activeRangeChange", [@getActiveRange()]
	
	getHoverPosition: => @_hoverPosition
	setHoverPosition: (position) =>
		@_hoverPosition = position
		$(@).trigger "hoverPositionChange", position

@TrusasCursor = TrusasCursor

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
	for opt in opts
	  [name, value] = opt.split '=', 2
		r[name.trim()] = value if name
	
	[r._type, r._subtype] = (v.trim() for v in type.split '/', 2)
	return r

