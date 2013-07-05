import numpy as np
import scipy.stats
import scipy.interpolate
import pyproj

from numba import autojit

class VehicleParticleFilter:
	def __init__(self,
			init_positions,
			init_speeds = np.array([0, 0]),
			yaw_dist=scipy.stats.norm(0, 10),
			accel_dist=scipy.stats.norm(0, 1),
			measurement_dist=scipy.stats.norm(0, 1),
			n_particles=1000,
			):
		self.yaw_dist = yaw_dist
		self.accel_dist = accel_dist
		self.measurement_dist = measurement_dist
		self.n_particles = n_particles
		dtype = [
			('x', np.float),
			('y', np.float),
			('sx', np.float),
			('sy', np.float),
			('weights', np.float),
			]


		self.particles = np.zeros(self.n_particles, dtype).view(np.recarray)
		self.particles.x = init_positions.T[0]
		self.particles.y = init_positions.T[1]
		self.particles.sx = init_speeds.T[0]
		self.particles.sy = init_speeds.T[1]
		self.particles.weights = 1.0/float(len(self.particles))
	
	def _predict(self, dt, particles=None):
		if particles is None: particles = self.particles
		n = len(particles)
		yaws = self.yaw_dist.rvs(n)
		xaccels = self.accel_dist.rvs(n)
		yaccels = self.accel_dist.rvs(n)
		particles.sx += xaccels*dt
		particles.sy += yaccels*dt

		particles.x += particles.sx*dt
		particles.y += particles.sy*dt

		particles.weights += self.accel_dist.logpdf(xaccels)
		particles.weights += self.accel_dist.logpdf(yaccels)
	
	def _measurement(self, measurement, particles=None):
		if particles is None: particles = self.particles
		dx = measurement[0] - particles.x
		dy = measurement[1] - particles.y
		p = self.measurement_dist.logpdf(dx) + self.measurement_dist.logpdf(dy)
		particles.weights += p
		
		lognormer = logprobsum(particles.weights)
		particles.weights -= lognormer
	
	def _resample(self, particles=None):
		if particles is None: particles = self.particles
		particles.weights -= logprobsum(particles.weights)
		sampled = logweightsample(particles.weights)

		particles[:] = particles[sampled]
		particles.weights = -1.0
		particles.weights -= logprobsum(particles.weights)
	
	def _hybridstep(self, dt, measurement):
		forward = self.particles.copy()

		self._predict(dt, forward)
		self._measurement(measurement, forward)
		
		backward = self.particles.copy()
		self._backpredict(dt, measurement, backward)
		pool = np.hstack((forward, backward)).view(np.recarray)

		pool.weights -= logprobsum(pool.weights)
		sample = logweightsample(pool.weights, len(self.particles))
		self.particles = pool[sample]
		self.particles.weights = -1.0
		self.particles.weights -= logprobsum(self.particles.weights)
	
	def _reversestep(self, dt, measurement):
		sample = logweightsample(self.particles.weights, 10*len(self.particles))
		tmp = self.particles[sample]
		self._backpredict(dt, measurement, tmp)
		self.particles = tmp[logweightsample(tmp.weights, len(self.particles))]
		self.particles.weights = -1
		self.particles.weights -= logprobsum(self.particles.weights)


	
	def _backpredict(self, dt, measurement, tmp):
		n = len(tmp)
		
		cx = self.measurement_dist.rvs(len(tmp)) + measurement[0]
		cy = self.measurement_dist.rvs(len(tmp)) + measurement[1]

		dx = cx - tmp.x
		dy = cy - tmp.y
		
		sx = dx/dt
		sy = dy/dt
		
		ax = (tmp.sx - sx)/dt
		ay = (tmp.sy - sy)/dt
		
		tmp.weights += self.accel_dist.logpdf(ax)
		tmp.weights += self.accel_dist.logpdf(ay)
		tmp.weights -= logprobsum(tmp.weights)

		tmp.x = cx
		tmp.y = cy
		tmp.sx = sx
		tmp.sy = sy

	
		"""
		peek_particles = self.particles.copy()
		self._predict(dt, peek_particles)
		self._measurement(measurement, peek_particles)
		self.particles.weights += peek_particles.weights
		#self._resample(peek_particles)
		#self.particles = peek_particles
		
		self._predict(dt)
		self._measurement(measurement)
		#self._resample()
		#self.particles.weights -= logprobsum(self.particles.weights)
		"""
		
	def step(self, dt, measurement):
		"""
		self._predict(dt)
		self._measurement(measurement)
		self._resample()
		return np.mean(self.particles.x), np.mean(self.particles.y)
		"""
		
		self._reversestep(dt, measurement)
		#self._predict(dt)
		#self._measurement(measurement)
		weights = np.exp(self.particles.weights)
		#return np.dot(weights, self.particles.x), np.dot(weights, self.particles.y)
		return np.mean(self.particles.x), np.mean(self.particles.y)


def utm_zone(lat, lon):
	# Adapted from ROS-project's geodesy-module
	# https://github.com/ros-geographic-info/geographic_info
	if -180.0 > lon or lon > 180.0:
        	raise ValueError('invalid longitude: ' + str(lon))
	zone = int((lon + 180.0)//6.0) + 1
	band = ' '
	if	84 >= lat and lat >= 72: band = 'X'
	elif  72 > lat and lat >= 64:  band = 'W'
	elif  64 > lat and lat >= 56:  band = 'V'
	elif  56 > lat and lat >= 48:  band = 'U'
	elif  48 > lat and lat >= 40:  band = 'T'
	elif  40 > lat and lat >= 32:  band = 'S'
	elif  32 > lat and lat >= 24:  band = 'R'
	elif  24 > lat and lat >= 16:  band = 'Q'
	elif  16 > lat and lat >= 8:   band = 'P'
	elif   8 > lat and lat >= 0:   band = 'N'
	elif   0 > lat and lat >= -8:  band = 'M'
	elif  -8 > lat and lat >= -16: band = 'L'
	elif -16 > lat and lat >= -24: band = 'K'
	elif -24 > lat and lat >= -32: band = 'J'
	elif -32 > lat and lat >= -40: band = 'H'
	elif -40 > lat and lat >= -48: band = 'G'
	elif -48 > lat and lat >= -56: band = 'F'
	elif -56 > lat and lat >= -64: band = 'E'
	elif -64 > lat and lat >= -72: band = 'D'
	elif -72 > lat and lat >= -80: band = 'C'
	else: raise ValueError('latitude out of UTM range: ' + str(lat))
	return (zone, band)

def get_projector(lat, lon):
	zone, band = utm_zone(lat, lon)
	return pyproj.Proj(proj='utm', zone=zone, datum='WGS84')

def reweighted_spline_smoother(u, x, reps=1e-6, sdCriteria=0.1, max_iters=100):
	demo_u = np.arange(u[0], u[-1], 0.1)
	demo_fit = None
	weights = np.ones(len(u))
	prev_sd = np.std(weights)
	s = np.sqrt(2*len(x))
	for i in range(max_iters):
		coeffs = scipy.interpolate.splprep(x, u=u, w=weights, s=s, k=3)[0]
		break
		fitted = np.vstack(scipy.interpolate.splev(u, coeffs))
		diffs = x - fitted
		diffs = diffs**2
		diffs = np.sqrt(np.sum(diffs, axis=0))
		weights = 1.0/(diffs+reps)
		sd = np.std(weights)
		if np.abs(prev_sd - sd) < sdCriteria:
			break
		print np.abs(prev_sd - sd)
		prev_sd = sd


		plt.plot(x[0], x[1], '.-')

		demo_fit = scipy.interpolate.splev(demo_u, coeffs)
		plt.plot(demo_fit[0], demo_fit[1])
		
		#plt.subplot(2,1,1)
		#plt.plot(u, x[0], '.-')
		#plt.plot(demo_u, demo_fit[0])
		
		#plt.subplot(2,1,2)
		##plt.plot(u, x[1], '.-')
		#plt.plot(demo_u, demo_fit[1])
		plt.show()
	
	return coeffs

def filter_track(track, new_dt=1.0, proj=None):
	if proj is None:
		lat, lon = track[0]['latitude', 'longitude']
		proj = get_projector(lat, lon)
	
	track = track[np.argsort(track['ts'])]
	dupes = np.diff(track['ts']) == 0
	track = track[~dupes]
	t = track['ts']
	latlon = track[['latitude', 'longitude']]
	lonlat = latlon[:,::-1]
	cartesian = np.vstack(proj(*lonlat.T)).T
	
	filt = VehicleParticleFilter(cartesian[0])

	def plot_filter_state(c):
		plt.plot(filt.particles.x, filt.particles.y, '.')
		plt.plot(cartesian.T[0], cartesian.T[1])
		plt.plot(c[0], c[1], 'o')
		plt.xlim(np.min(filt.particles.x), np.max(filt.particles.x))
		plt.ylim(np.min(filt.particles.y), np.max(filt.particles.y))


	prev_t = t[0]
	filtered = []
	stds = []
	
	for i in range(1, len(cartesian)):
		print i/float(len(cartesian))*100
		dt = t[i] - prev_t
		prev_t = t[i]
		c = cartesian[i]
		filtered.append(filt.step(dt, c))
		continue
		#filt._predict(dt)
		plot_filter_state(c)
		#plt.show()
		#filt._measurement(c)
		x = filt.particles.x
		y = filt.particles.y
		plt.plot(filt.particles.x, filt.particles.y, '.')
		#plt.plot([x, x+filt.particles.sx],
		#	[y, y+filt.particles.sy], 'k-', alpha=0.1)
		#plot_filter_state(c)
		plt.show()
	
	filtered = np.array(filtered)
	#weights = 1.0/np.array(stds)
	#coeffs = scipy.interpolate.splprep(filtered.T, u=t[1:], k=3, w=weights, s=len(weights))[0]
	#values = scipy.interpolate.splev(t, coeffs)
	#plt.plot(filtered[:,0], filtered[:,1], 'g.-')
	#plt.plot(values[0], values[1], color='red')
	#plt.plot(cartesian[:,0], cartesian[:,1], 'k.-')
	#plt.show()
	return

def gaussian_interp(t, coords, std, max_win=10):
	var = 2*std**2
	logpdf = lambda t, nt: (-(t-nt)**2/var)
	weights_hack = [np.zeros(len(t))]
	def interp(new_t):
		nearest = t.searchsorted(new_t)
		s = slice(max(nearest-max_win, 0), nearest+max_win)
		weights = logpdf(t[s], new_t)
		weights -= logprobsum(weights)
		weights = np.exp(weights)
		return np.average(coords[s], weights=weights, axis=0)
	return interp

def smooth_track(track, proj=None, new_dt=0.1):
	if proj is None:
		lat, lon = track[0]['latitude'], track[0]['longitude']
		proj = get_projector(lat, lon)
	
	track = track[np.argsort(track['ts'])]
	dupes = np.diff(track['ts']) == 0
	track = track[~dupes]
	t = track['ts']
	latlon = np.vstack((track.latitude, track.longitude)).T
	lonlat = latlon[:,::-1]
	cartesian = np.vstack(proj(*lonlat.T)).T
	
	lininterp = scipy.interpolate.interp1d(t, cartesian.T)
	grid_t = np.arange(t[0], t[-1], 1.0)
	grid_cart = lininterp(grid_t)
	
	new_t = np.arange(t[0], t[-1], new_dt)
	values = gaussian_interp(grid_t, grid_cart.T, 1.0)
	values = np.array(map(values, new_t))

	diffs = np.diff(values, axis=0)

	speed = np.sqrt(diffs[:,0]**2 + diffs[:,1]**2)/new_dt
	bearing = np.degrees(np.arctan2(diffs[:,0], diffs[:,1]))
	
	altinterp = scipy.interpolate.interp1d(t, track['elevation'])
	grid_alt = altinterp(grid_t)
	altitude = gaussian_interp(grid_t, grid_alt, 1.0)
	altitude = np.array(map(altitude, new_t))
	
	latlon = np.vstack(proj(*values.T, inverse=True))[::-1]
	
	return np.rec.fromarrays((new_t[1:], latlon[0,1:],
			latlon[1,1:], speed, bearing, altitude[1:]),
		names="ts,latitude,longitude,speed,bearing,elevation")
	
	lininterp = scipy.interpolate.interp1d(t, cartesian.T)
	grid_t = np.arange(t[0], t[-1], 1.0)
	grid_cart = lininterp(grid_t)
	coeffs = reweighted_spline_smoother(grid_t, grid_cart)

	new_t = np.arange(t[0], t[-1], new_dt)
	values = scipy.interpolate.splev(new_t, coeffs)

	diffs = np.vstack(scipy.interpolate.splev(new_t, coeffs, der=1))
	
	speed = np.apply_along_axis(np.linalg.norm, 0, diffs)
	bearing = np.degrees(np.arctan2(diffs[0], diffs[1]))

	latlon = np.vstack(proj(*values, inverse=True))[::-1]

	#spline = scipy.interpolate.interp1d(
	#	track[:,0], latlon, axis=0)

	return np.rec.fromarrays(new_t, latlon[0], latlon[1], speed, bearing,
		names="ts,latitude,longitude,speed,bearing")

def logprobsum(logprobs):
	m = np.max(logprobs)
	return m + np.log(np.sum(np.exp(logprobs - m)))

def logprobnorm(logprobs):
	return logprobs - logprobsum(logprobs)

def logweightsample(logprobs, n_samples=None, scaler=1e6):
	# TODO: Does this really make any sense?
	scaled = np.exp(logprobnorm(logprobs) + np.log(scaler))
	cumweights = np.cumsum(scaled)
	# TODO: What's the numerical accuracy of [0..1)*scaler?
	if n_samples is None:
		n_samples = len(logprobs)
	rand = np.random.rand(n_samples)*cumweights[-1]
	sample = np.searchsorted(cumweights, rand)
	return sample

if __name__ == '__main__':

	#rand = np.log(np.random.rand(10))
	#logweightsample(rand)
	#asdf
	from gpx_provider import gpx_to_track
	import sys
	import matplotlib.pyplot as plt
	track = gpx_to_track(sys.stdin.read())

	#filtered, speed, bearing = filter_track(track)
	track = smooth_track(track)
	
	#plt.plot(track[:,1], track[:,2], '.-')
	#plt.plot(filtered[:,1], filtered[:,2])

	
	#plt.plot(filtered[:,0], filtered[:,1])
	#plt.plot(track[:,0], track[:,1], '.-')

	plt.plot(track['ts'], track['speed'])
	plt.show()
