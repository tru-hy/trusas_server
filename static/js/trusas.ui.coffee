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
				t = ctrl.toSessionTime(ui.value)
				content = handleTipContent t
				handle.data "powertip", content
				$("#powerTip").html(content)
	
	$ctrl = $(ctrl)
	$ctrl.on "durationchange", (e) ->
		seekbar.slider("option", "max", ctrl.getDuration())
		$("#playback_control .session_date #total").html(
				format_time(ctrl.getDuration())
				)
	
	format_session_time = (t) -> "#{t.toFixed(2)}s"

	handle = seekbar.find(".ui-slider-handle")
	$ctrl.on "timeupdate", (e) ->
		t = ctrl.getCurrentTime()
		seekbar.slider "value", t

	handleTipContent = (t) ->
		"""
		<p>Timestamp: #{format_session_time(t)}
		<button title="Add annotation" class="btn btn-success btn-mini pull-right add-annotation-btn">
		+
		</button>
		</p>
		"""
	
	handleTipOpts =
		placement: 's'
		mouseOnToPopup: true
		smartPlacement: true
		closeDelay: 500
	
	$("body").on "click", '.popover .annotation-form .btn-cancel', ->
		annotid = $(@).data 'annotid'
		annot = $ """.annotation-marker[data-annotid="#{annotid}"]"""
		annot.popover("destroy")
		annot.remove()
	
	$("body").on "click", '.popover .annotation-form .btn-success', ->
		annotid = $(@).data 'annotid'
		annot = $ """.annotation-marker[data-annotid="#{annotid}"]"""
		text = $(@).parents('.annotation-form').first().find('textarea').first()
		annot.popover("destroy")
		annot.remove()
		
		###
		annot.popover
			trigger: 'click'
			placement: 'bottom'
			html: false
			content: text.val()
		annot.popover("show")
		###
	
	add_annotation = (gtime, text) ->
		cont = $("#playback_control #annotations")
		pos = t/ctrl.getDuration()*100
		
		# A hack to find the proper elements in handlers
		annotid = "data-annotid=\"#{Math.random()}\""

		t = ctrl.toStreamTime gtime
		title = format_session_time gtime


	new_annotation = (t) ->
		cont = $("#playback_control #annotations")
		pos = t/ctrl.getDuration()*100
		
		# A hack to find the proper elements in handlers
		annotid = "data-annotid=\"#{Math.random()}\""

		gtime = ctrl.toSessionTime t
		title = format_session_time gtime
		annot = $ """
			<li #{annotid} data-timestamp="#{gtime}"
				title=#{title}
				class="annotation-marker" style="left: #{pos}%"></li>
			"""
		
		form = $ """
			<div class="annotation-form">
			<textarea>
			</textarea>
			<div>
			<button #{annotid} class="btn btn-cancel">Cancel</button>
			<button #{annotid} class="btn btn-success pull-right">Add</button>
			</div>
			</div>
			"""
		
		textarea = form.find("textarea")
		
		
		cont.append(annot)
		annot.popover
			trigger: 'manual'
			placement: 'bottom'
			html: true
			content: form
		annot.popover("show")


	$("#powerTip").on "click", ".add-annotation-btn", ->
		$.powerTip.closeTip()
		new_annotation seekbar.slider "value"

	handle.powerTip handleTipOpts
		
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
	

