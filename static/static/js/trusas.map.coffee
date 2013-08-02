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
		@_hoverpos = [0, 0]
		@_hovermarker = $(marker)
		.attr("r", 10)
		.attr("display", "none")
		@map.on "move", @_render_hover
		
		layer = svg.appendChild(po.svg 'g')
		marker = layer.appendChild(po.svg 'path')
		@_activepath = []
		@_activepath_el = $(marker)
		.attr("stroke-width", 10)
		.attr("fill", "none")
		.attr("display", "none")
		.attr("stroke", "black")
		.attr("vector-effect", "non-scaling-stroke")
		@map.on "move", @_render_activepath

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
		@_hoverpos = pos
		@_render_hover()
	
	_render_hover: =>
		pos = @_hoverpos
		if not pos or not pos[0]
			@_hovermarker.attr("display", "none")
			return
		
		p = @map.locationPoint lat: pos[0], lon: pos[1]
		trans = "translate(#{p.x}, #{p.y})"
		@_hovermarker.attr("transform", trans)
		@_hovermarker.attr("display", "inline")

	
	set_active_path: (coords) =>
		@_activepath = coords
		@_render_activepath()
	
	_render_activepath: =>
		if @_activepath.length == 0
			@_activepath_el.attr("display", "none")
			return
		
		# TODO: Clipping would probably be faster
		line = d3.svg.line()
		.x((d) -> d.x)
		.y((d) -> d.y)
		mapped = []
		for p in @_activepath
			mapped.push @map.locationPoint(lat: p[0], lon: p[1])
		d = line(mapped)
		@_activepath_el.attr("d", d)
		@_activepath_el.attr("display", "inline")
	
		
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

`
// Adapted from C++ code in wikipedia Cohen-Shuterland page
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
	var full = false;
 
	while (true) {
		if (!(outcode0 | outcode1)) { // Bitwise OR is 0. Trivially accept and get out of loop
			accept = true;
			full = true;
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
		return [false, false];
	}

	return [[[x0, y0], [x1, y1]], full];
}
`

t_at_point = (p, span) ->
	[[x0, y0], [x1, y1]] = span
	spanlen = Math.sqrt(Math.pow(x0-x1, 2) + Math.pow(y0-y1, 2))
	projlen = Math.sqrt(Math.pow(p[0]-x0, 2) + Math.pow(p[1]-y0, 2))
	return projlen/spanlen

clipped_distspan = (bbox, c0, c1, dists) ->
	[clipped, isfull] = CohenSutherlandLineClip(c0[0], c0[1], c1[0], c1[1], bbox)
	return false if not clipped
	dist = dists[1] - dists[0]
	a = t_at_point(clipped[0], [c0, c1])*dist+dists[0]
	b = t_at_point(clipped[1], [c0, c1])*dist+dists[0]
	return [a, b]


Trusas.clipped_linestrings = (bbox, coords, dists) ->
	inside = []
	i = 0
	n = coords.length-1
	while i < n
		c0 = coords[i]
		c1 = coords[i+1]
		clipped = clipped_distspan bbox, c0, c1, [dists[i], dists[i+1]]
		if not clipped
			++i; continue
		current = clipped
		inside.push(current); ++i
		while i < n
			c0 = coords[i]
			c1 = coords[i+1]
			clipped = clipped_distspan bbox, c0, c1, [dists[i], dists[i+1]]
			if clipped[0] != dists[i] # New non-continuous span
				# TODO Does a recalc of the clipped to simplify flow
				break
			current[1] = clipped[1]
			++i
	return inside

Trusas.longest_clipped_linestring = (bbox, coords, dists) ->
	inside = Trusas.clipped_linestrings bbox, coords, dists
	maxlen = -1
	maxspan = [NaN, NaN]
	for span in inside
		slen = span[1] - span[0]
		if slen > maxlen
			maxlen = slen
			maxspan = span
	return maxspan

	

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
