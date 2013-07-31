class Trusas.Map
	@Create: (el) ->
		self = new Trusas.Map(el)
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
		
