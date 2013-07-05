import providers
from xml.etree import ElementTree
import datetime
import time
from StringIO import StringIO
import json
import pyproj
import numpy as np

from track_filter import smooth_track

def _gpx_to_track(data):
	# Does somebody really use this namespace crap? And
	# why doesn't etree let me ignore it?
	data = data.replace("xmlns=", "xmlnamespace=")
	output = StringIO()

	root = ElementTree.fromstring(data)
	# TODO: Stupid. Assumes there's only one track
	points = root.findall('.//trkpt')
	prevPos = None

	for el in points:
		t = el.find('time')
		if t is None:
			continue
		t = t.text
		t = time.strptime(t, '%Y-%m-%dT%H:%M:%S.%fZ')
		t = time.mktime(t)
		lat = float(el.attrib['lat'])
		lon = float(el.attrib['lon'])
		elev = el.find('ele')
		if elev is not None:
			elevation = float(elev.text)
		else:
			elevation = None

		yield t, lat, lon, elevation

def gpx_to_track(data):
	records = list(_gpx_to_track(data))
	return np.rec.fromrecords(records, names=['ts', 'latitude', 'longitude', 'elevation'])
		

ellipsoid = pyproj.Geod(ellps="WGS84")
def point_diff(latlon1, latlon2):
	bearing, _, dist = ellipsoid.inv(latlon1[1], latlon1[0],
		latlon2[1], latlon2[0])
	return [bearing, dist]

class GpxProvider(providers.PathProvider):
	def __init__(self, mypath, gpxfile,
		content_type="application/vnd.trusas.location"):
		self.gpxfile = gpxfile
		self.data = None
		super(GpxProvider, self).__init__(mypath, content_type)
	
	def handle(self, **kwargs):
		track = gpx_to_track(self.gpxfile.read())
		track = smooth_track(track)
		self.gpxfile.seek(0)

		output = StringIO()
		print "Got track"
		
		for i, point in enumerate(track):
			hdr = dict(ts=point['ts'])
			d = dict(
				latitude=point['latitude'],
				longitude=point['longitude'],
				speed=point['speed'],
				bearing=point['bearing'],
				elevation=point['elevation'],
				)
			d = json.dumps([hdr, d])
			output.write(d)
			output.write("\n")


		output.seek(0)
		return output
		
		for el in points:
			t = el.find('time')
			if t is None:
				continue
			t = t.text
			t = time.strptime(t, '%Y-%m-%dT%H:%M:%S.%fZ')
			t = time.mktime(t)
			lat = float(el.attrib['lat'])
			lon = float(el.attrib['lon'])
			
			hdr = dict(ts=t)
			d = dict(
				latitude=lat,
				longitude=lon
				)
			
			if prevPos is not None:
				[bearing, dist] = point_diff(
					prevPos[1],
					(lat, lon))
				dt = t - prevPos[0]
				if dt <= 0:
					continue
				else:
					speed = dist/dt
			else:
				speed = None
				bearing = None
			
			d['speed'] = speed
			d['bearing'] = bearing

			prevPos = (t, (lat, lon))
			elev = el.find('ele')
			if elev is not None:
				d['elevation'] = float(elev.text)

			d = json.dumps([hdr, d])
			output.write(d+"\n")
		
		output.seek(0)
		return output

if __name__ == '__main__':
	import sys
	import session_server

	session_server.run_with_providers([GpxProvider("location2.jsons", open(sys.argv[1]))])
