import cherrypy as cp
import os
from os import path
from cherrypy.lib.static import serve_file, serve_fileobj


def is_fileobject(obj):
	has = lambda attr: hasattr(obj, h) and callable(getattr(obj, h))
	return has('read') and has('seek')

class SessionServer(object):
	DEFAULT_STATIC_PATH = path.join(path.dirname('__file__'), 'static')
	def __init__(self, providers, static_path=DEFAULT_STATIC_PATH):
		self.providers = providers
		self.static_path = path.abspath(static_path)
	
	@cp.expose
	def default(self, *path, **kwargs):
		if len(path) == 0:
			path = ['index.html']
		
		path = os.path.join(*path)
		print "Serving", path
		for provider in self.providers:
			result = provider(path=path, **kwargs)
			if result is not None:
				return self._serve_result(result)

		return self.serve_static(path)
	
	def _serve_result(self, result):
		hdr, data = result
		cp.response.headers['Content-Type'] = hdr['Content-Type']
		if isinstance(data, basestring):
			return serve_file(data)
		if is_fileobject(data):
			return serve_fileobj(data)
		

	@cp.expose
	@cp.tools.json_out()
	def resources_json(self):
		res = {}
		for provider in self.providers[::-1]:
			res.update(provider.provides)
		return res
	
	def serve_static(self, path):
		path = os.path.abspath(os.path.join(self.static_path, path))
		# TODO: I wish there's a more standard implementation for this
		if not path.startswith(self.static_path):
			raise cp.HTTPError(400, "Bad Request. I'm on to you and your slashes and dots!")
		return serve_file(path)

def run_with_providers(providers):

	config = {
			'server.socket_host': '0.0.0.0',
			'server.thread_pool': 100,
			'tools.sessions.locking': 'explicit'
			}

	cp.quickstart(SessionServer(providers), '/',
		config={'global': config})
	
