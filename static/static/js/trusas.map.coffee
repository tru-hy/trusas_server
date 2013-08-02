po = org.polymaps

class Trusas.PolymapsMap
	@Create: (el) ->
		self = new Trusas.PolymapsMap(el)
		return self.ready
	
	constructor: (@el) ->
		@_synthetic_move = false

		svg = @el.appendChild(po.svg('svg'))
		@map = po.map()
		.container(svg)
		.add(po.interact())
		.zoomRange(null)
		
		#osmurl = po.url("http://{S}www.toolserver.org/tiles/bw-mapnik/{Z}/{X}/{Y}.png")
		#.hosts(['a.', 'b.'])
		osmurl = po.url("http://tile.openstreetmap.org/{Z}/{X}/{Y}.png")
		osmlayer = po.image().url(osmurl)
		.zoom((z) -> Math.min(z, 18))

		@map.add(osmlayer)

		
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
		@_synthetic_move = true
		@map.extent [{lat: extent[0][0], lon: extent[0][1]},
			{lat: extent[1][0], lon: extent[1][1]}]

	
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
	
	onmove: (cb) =>
		@map.on "move", =>
			# Don't signal on "synthetic" (self-triggered)
			# moves. Sort of hack, but helps avoiding signal
			# loops.
			if @_synthetic_move
				@_synthetic_move = false
				return

			ex = @map.extent()
			cb [[ex[0].lat, ex[0].lon], [ex[1].lat, ex[1].lon]]

Trusas.Map = Trusas.PolymapsMap

###
TODO: Fix me
`
// Shameless copypaste from wikipedia
INSIDE = 0; // 0000
LEFT = 1;   // 0001
RIGHT = 2;  // 0010
BOTTOM = 4; // 0100
TOP = 8;    // 1000
 
// Compute the bit code for a point (x, y) using the clip rectangle
// bounded diagonally by (xmin, ymin), and (xmax, ymax)
 
// ASSUME THAT xmax, xmin, ymax and ymin are global constants.
 
// Cohen-Sutherland clipping algorithm clips a line from
// P0 = (x0, y0) to P1 = (x1, y1) against a rectangle with 
// diagonal from (xmin, ymin) to (xmax, ymax).
CohenSutherlandLineClip = function(x0, y0, x1, y1, bbox)
{
var xmin = bbox[0][0];
var xmax = bbox[1][0];
var ymin = bbox[0][1];
var ymax = bbox[1][1];

ComputeOutCode = function(x, y)
{
	var code;
 
	code = INSIDE;	  // initialised as being inside of clip window
 
	if (x < xmin)	   // to the left of clip window
		code |= LEFT;
	else if (x > xmax)      // to the right of clip window
		code |= RIGHT;
	if (y < ymin)	   // below the clip window
		code |= BOTTOM;
	else if (y > ymax)      // above the clip window
		code |= TOP;
 
	return code;
}

	// compute outcodes for P0, P1, and whatever point lies outside the clip rectangle
	var outcode0 = ComputeOutCode(x0, y0);
	var outcode1 = ComputeOutCode(x1, y1);
	var accept = false;
 
	while (true) {
		if (!(outcode0 | outcode1)) { // Bitwise OR is 0. Trivially accept and get out of loop
			accept = true;
			break;
		} else if (outcode0 & outcode1) { // Bitwise AND is not 0. Trivially reject and get out of loop
			break;
		} else {
			// failed both tests, so calculate the line segment to clip
			// from an outside point to an intersection with clip edge
			var x, y;
 
			// At least one endpoint is outside the clip rectangle; pick it.
			var outcodeOut = outcode0 ? outcode0 : outcode1;
 
			// Now find the intersection point;
			// use formulas y = y0 + slope * (x - x0), x = x0 + (1 / slope) * (y - y0)
			if (outcodeOut & TOP) {	   // point is above the clip rectangle
				x = x0 + (x1 - x0) * (ymax - y0) / (y1 - y0);
				y = ymax;
			} else if (outcodeOut & BOTTOM) { // point is below the clip rectangle
				x = x0 + (x1 - x0) * (ymin - y0) / (y1 - y0);
				y = ymin;
			} else if (outcodeOut & RIGHT) {  // point is to the right of clip rectangle
				y = y0 + (y1 - y0) * (xmax - x0) / (x1 - x0);
				x = xmax;
			} else if (outcodeOut & LEFT) {   // point is to the left of clip rectangle
				y = y0 + (y1 - y0) * (xmin - x0) / (x1 - x0);
				x = xmin;
			}
 
			// Now we move outside point to intersection point to clip
			// and get ready for next pass.
			if (outcodeOut == outcode0) {
				x0 = x;
				y0 = y;
				outcode0 = ComputeOutCode(x0, y0);
			} else {
				x1 = x;
				y1 = y;
				outcode1 = ComputeOutCode(x1, y1);
			}
		}
	}

	if(!accept) {
		return false;
	}

	return [x0, y0, x1, y1];
}
`


Trusas.clipped_linestrings = (bbox, coords, dists) ->
	inside = []
	for i in [1...coords.length-1]
		c0 = coords[i]
		c1 = coords[i+1]
		clipped = CohenSutherlandLineClip(c0[0], c0[1], c1[0], c1[1], bbox)
		if clipped
			inside.push [i, i+1]

	return inside
###

###
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
###
