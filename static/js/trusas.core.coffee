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


		notify_if_complete = ->
			return if completion_notified
			return if not handlers_notified
			for target in loading
				if target not in loaded
					return
			completion_notified = true
			on_load_complete()
			
		register = (param, element, {calls, events}={}) =>
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

				if handler ctrl, register, param
					loading.push param
		
		handlers_notified = true
		notify_if_complete()

  
	loader = (resources) => load_handlers(complete, resources, oncreated, getcontainer)
	if typeof(resources) == 'string'
		$.getJSON resources, loader
	else
	  loader resources
	return ctrl


class TrusasController
	constructor: ->
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
		c?.setCurrentTime ts for c in @_controllees
	
	getCurrentTime: =>
		t = @_currentTime - @_firstTime
		return 0.0 if isNaN t
		return t

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


