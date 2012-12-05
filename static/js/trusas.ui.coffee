# TODO: This is really ugly stuff moved from prototyping code
@trusas_create_ui = (opts={}) ->
	grid_size = 140
	grid_margin = 10
		
	container = $ ".gridster ul"
	widget_size = (el) ->
		# This is stupid
		$el = $(el)
		return [5, 3] if $el.is("video")
		
		return [1, 1]
	
	provide_container = (param) ->
		{width, height, callback} = param
		wrapper = $("""
			<li data-sizex="#{width ? 1}"
			    data-sizey="#{height ? 1}"
			    data-row="1" data-col="1">
			</li>
			""").appendTo(container)
		callback wrapper

	resizeBlock = (gridster, elmObj) ->
		elmObj = $(elmObj)
		w = elmObj.width() - grid_size
		h = elmObj.height() - grid_size
		
		grid_w = 1
		while w > 0
			w -= (grid_size + (grid_margin * 2))
			grid_w++
			
		grid_h = 1
		while h > 0
			h -= (grid_size + (grid_margin * 2))
			grid_h++

		gridster.resize_widget(elmObj, grid_w, grid_h)
	
	initialize_grid = ->
		gridster = container.gridster(
				widget_margins: [grid_margin, grid_margin],
				widget_base_dimensions: [grid_size, grid_size],
				max_size_x: 10).data "gridster"
		container.find(".gs_w").resizable
			grid: [grid_size + (grid_margin * 2), grid_size + (grid_margin * 2)],
			animate: false,
			minWidth: grid_size,
			minHeight: grid_size,
			#containment: '#content ul',
			autoHide: true,
			stop: (event, ui) ->
				resized = $(this)
				setTimeout (-> resizeBlock(gridster, resized)), 300
		container.find('.ui-resizable-handle').hover(
			-> gridster.disable(),
			-> gridster.enable())


	opts.complete = initialize_grid
	opts.getcontainer = provide_container
	ctrl = new_trusas_controller opts
	
	seekbar = $ "#playback_control .seekbar"
	seekbar.slider min: 0, max: 0, step: 0.1,
			slide: (ev, ui) ->
				ctrl.setCurrentTime ui.value,
				$("#playback_control .session_date #current").html(
					format_time(ui.value))
			change: (ev, ui) ->
				$("#playback_control .session_date #current").html(
					format_time(ui.value))
	
	$ctrl = $(ctrl)
	$ctrl.on "durationchange", (e) ->
		seekbar.slider("option", "max", ctrl.getDuration())
		$("#playback_control .session_date #total").html(
				format_time(ctrl.getDuration())
				)

	$ctrl.on "timeupdate", (e) ->
		seekbar.slider("value", ctrl.getCurrentTime())
	
	$("#playback_control .play_toggle").click (ev) ->
		if ctrl.isPaused()
			ctrl.play()
			$(@).parent().addClass("active")
		else
			ctrl.pause()
			$(@).parent().removeClass("active")

	return ctrl

format_time = (sec_numb) ->
	sec_numb = Math.round(sec_numb)
	hours   = Math.floor(sec_numb / 3600)
	minutes = Math.floor((sec_numb - (hours * 3600)) / 60)
	seconds = sec_numb - (hours * 3600) - (minutes * 60)

	if (hours < 10)
		hours  = "0"+hours
	if (minutes < 10)
		minutes = "0"+minutes
	if (seconds < 10)
		seconds = "0"+seconds
	return  hours+':'+minutes+':'+seconds
	

