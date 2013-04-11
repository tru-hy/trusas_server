import os
from providers import FileProvider, AuxProvider, AnnotationProvider
import uuid

def _basename_filter(target, path):
	if os.path.basename(path) != target:
		raise StopIteration

video_mimetypes = {
	'.mkv': 'video/x-matroska',
	'.webm': 'video/webm'
}

def _prober_video(f, d):
	_, ext = os.path.splitext(f)
	if not (ext in video_mimetypes and f+'.sync' in d): return
	
	vid = FileProvider(f, video_mimetypes[ext])
	sync = FileProvider(f+'.sync',
		'application/vnd.trusas.timemap') 
	yield AuxProvider(vid, ('timemap', sync))

def _prober_location(f, d):
	_basename_filter('location.jsons', f)
	yield FileProvider(f, 'application/vnd.trusas.location')

def _prober_androidlocation(f, d):
	_basename_filter('location_android.jsons', f)
	yield FileProvider(f, 'application/vnd.trusas.android-location')

def _prober_smarteye(f, d):
	_basename_filter('smarteye.jsons', f)
	yield FileProvider(f, 'application/vnd.trusas.tru.smarteye')

def _prober_sensors(f, d):
	_basename_filter('sensors.jsons', f)
	yield FileProvider(f, 'application/vnd.trusas.sensors')




def probe_trusas_spec(directory):
	providers = []
	contents = os.listdir(directory)
	contents = [os.path.join(directory, f) for f in contents]
	# I would do a list of anonymous functions if this damn
	# language would have a non-crippled lambdas
	probers = [v for k, v in globals().items()
		if k.startswith("_prober")]
	for f in contents:
		for p in probers:
			providers.extend(p(f, contents))
	
	if len(providers) > 0:
		providers.append(AnnotationProvider(directory))
	return providers

if __name__ == '__main__':
	import sys
	import session_server as session_server
	session_server.run_dir_prober(sys.argv[1], probe_trusas_spec)
