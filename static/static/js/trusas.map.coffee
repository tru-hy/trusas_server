po = org.polymaps

class Trusas.PolymapsMap
	@Create: (el) ->
		self = new Trusas.PolymapsMap(el)
		return self.ready
	
	constructor: (@el) ->
		svg = @el.appendChild(po.svg('svg'))
		@map = po.map()
		.container(svg)
		.add(po.interact())
		.zoomRange(null)
		
		osmurl = po.url("http://{S}www.toolserver.org/tiles/bw-mapnik/{Z}/{X}/{Y}.png")
		.hosts(['a.', 'b.'])
		#osmurl = po.url("http://tile.openstreetmap.org/{Z}/{X}/{Y}.png")
		@map.add(po.image().url(osmurl))

		
		layer = svg.appendChild(po.svg 'g')
		marker = layer.appendChild(po.svg 'circle')
		@hoverpos = [0, 0]
		@hovermarker = $(marker)
		.attr("r", 10)
		.attr("display", "none")

		@map.on "move", @_render_hover

		@ready = $.Deferred()
		@ready.resolve(@)
	
	add_route: (coords, id) =>
		coords = ([c[1], c[0]] for c in coords)
		geo = geometry:
			type: "LineString"
			coordinates: coords
		layer = po.geoJson().features([geo])
		
		style = po.stylist()
		.attr("fill", "none")
		.attr("stroke", "steelblue")
		.attr("stroke-width", 5)
		.attr("vector-effect", "non-scaling-stroke")

		layer.on "load", style
		@map.add(layer)

	add_marker: (coords, id) =>
		geo = geometry:
			type: "Point"
			coordinates: [coords[1], coords[0]]
		
		layer = po.geoJson().features([geo])

		style = po.stylist()
		
		layer.on "load", style
		.attr("r", 5)
		.attr("fill", "red")
		.attr("vector-effect", "non-scaling-stroke")

		@map.add(layer)



	set_extent: (extent) =>
		@map.extent [{lat: extent[1], lon: extent[0]}, {lat: extent[3], lon: extent[2]}]

	
	set_hover: (pos) =>
		# TODO: This isn't probably the most efficient, but
		#	I couldn't figure out how to make the stylist
		#	to give out the created element.
		@hoverpos = pos
		@_render_hover()
	
	_render_hover: =>
		pos = @hoverpos
		if not pos or not pos[0]
			@hovermarker.attr("display", "none")
			return
		
		p = @map.locationPoint lat: pos[0], lon: pos[1]
		trans = "translate(#{p.x}, #{p.y})"
		@hovermarker.attr("transform", trans)
		@hovermarker.attr("display", "inline")

Trusas.Map = Trusas.PolymapsMap

class Trusas.CesiumMap
	@Create: (el) ->
		self = new Trusas.CesiumMap(el)
		return self.ready

	constructor: (@el) ->
		@ellipsoid = Cesium.Ellipsoid.WGS84
		@polylines = new Cesium.PolylineCollection()
		opts = {}
		osm = new Cesium.OpenStreetMapImageryProvider
			url: 'http://tile.openstreetmap.org/'
		opts.imageryProvider = osm
		#opts.sceneMode = Cesium.SceneMode.SCENE2D
		@widget = new Cesium.CesiumWidget @el, opts
		camctrl = @widget.scene.getScreenSpaceCameraController()
		#camctrl.enableRotate = false
		camctrl.enableTilt = false
		@widget.scene.getPrimitives().add @polylines
		@routes = {}
		mp = @_generate_markers()
		@ready = $.Deferred()
		$.when(mp).done => @ready.resolve @
	
	_generate_markers: =>
		image = new Image()
		image.src = 'static/img/marker.png'
		promise = $.Deferred()
		image.onload = =>
			@billboards = new Cesium.BillboardCollection()
			texture_atlas = @widget.scene.getContext().createTextureAtlas
				image: image
			@billboards.setTextureAtlas texture_atlas
			@hovermarker = @billboards.add
				show: false
				imageIndex: 0
				verticalOrigin : Cesium.VerticalOrigin.BOTTOM
			@widget.scene.getPrimitives().add @billboards
			promise.resolve()
		return promise
	
	_cart: ([lat, lon]) ->
		@ellipsoid.cartographicToCartesian(
			Cesium.Cartographic.fromDegrees(lon, lat))
	
	add_route: (coords, id) =>
		material = Cesium.Material.fromType(undefined, 'Color')
		material.uniforms.color = red: 0.0, green: 0.5, blue: 1.0, alpha: 1.0
		routeline = @polylines.add
			width: 4
			material: material

		mangled = (Cesium.Cartographic.fromDegrees(p[1], p[0], 0) for p in coords)
		cart_route = @ellipsoid.cartographicArrayToCartesianArray(mangled)
		routeline.setPositions cart_route
		@routes[id] = routeline if id
	
	add_marker: (coords, id) =>
		marker = @billboards.add
			show: true
			imageIndex: 0
			verticalOrigin : Cesium.VerticalOrigin.BOTTOM
			position: @_cart coords
		
	set_extent: (extent) =>
		extent = new Cesium.Extent (Trusas.radians p for p in extent)...
		@widget.scene.getCamera().controller.viewExtent extent, @ellipsoid
	
	set_hover: (coords) =>
		if not @hovermarker?
			return

		if not coords
			@hovermarker.setShow false
			return
		pos = @_cart coords
		@hovermarker.setPosition pos
		@hovermarker.setShow true
		
