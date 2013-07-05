import cherrypy as cp
import os
from os import path
from cherrypy.lib.static import serve_file, serve_fileobj


def is_fileobject(obj):
	has = lambda attr: hasattr(obj, attr) and callable(getattr(obj, attr))
	return has('read') and has('seek')

DEFAULT_STATIC_PATH = path.join(path.dirname('__file__'), 'static')

class StaticServer(object):
	def __init__(self, static_path=DEFAULT_STATIC_PATH):
		self.static_path = path.abspath(static_path)
	
	@cp.expose
	def default(self, *path, **kwargs):
		if len(path) == 0:
			path = ['index.html']
		
		path = os.path.join(*path)
		return self.serve_static(path)
	
	def serve_static(self, path):
		path = os.path.abspath(os.path.join(self.static_path, path))
		# TODO: I wish there's a more standard implementation for this
		if not path.startswith(self.static_path):
			raise cp.HTTPError(400, "Bad Request. I'm on to you and your slashes and dots!")
		print path
		return serve_file(path)



	
	"""
	@cp.expose
	def default(self, *path, **kwargs):
		if len(path) == 0:
			path = ['index.html']
		
		path = os.path.join(*path)
		return self.serve_static(path)
	
	def serve_static(self, path):
		path = os.path.abspath(os.path.join(self.static_path, path))
		# TODO: I wish there's a more standard implementation for this
		if not path.startswith(self.static_path):
			raise cp.HTTPError(400, "Bad Request. I'm on to you and your slashes and dots!")
		print path
		return serve_file(path)
	"""

class ResourceServer(object):
	def __init__(self, providers):
		self.providers = providers
	
	@cp.tools.json_out()
	def index_json(self):
		res = {}
		for provider in self.providers[::-1]:
			res.update(provider.provides())
		return res
	cp.expose(index_json, 'index')

	@cp.expose
	def default(self, *path, **kwargs):
		path = os.path.join(*path)
		for provider in self.providers:
			result = provider(path=path, **kwargs)
			if result is not None:
				return self._serve_result(result)

		raise cp.NotFound()

	def _serve_result(self, result):
		hdr, data = result
		cp.response.headers['Content-Type'] = hdr['Content-Type']
		if isinstance(data, basestring):
			return serve_file(data)
		if is_fileobject(data):
			return serve_fileobj(data)
		

class RootServer(object):
	def __init__(self, providers, static_path=DEFAULT_STATIC_PATH):
		self.static = StaticServer(static_path)
		self.resources = ResourceServer(providers)
	
	@cp.expose
	def index(self):
		return self.static.serve_static('index.html')
	

cp_global_config = {
	'server.socket_host': '0.0.0.0',
	'server.thread_pool': 10,
	}

cp_app_config = {}
		

class Lister:
	def __init__(self):
		self.services = []

	@cp.expose
	def index(self):
		page = "<html><ul>"
		for name in sorted(self.services):
			page += '<li><a href="%s/">%s</a></li>'%(name, name)
		page += "</ul>"
		return page
		

def run_dir_prober(directory, prober):
	main = prober(directory)
	if len(main) > 0:
		return run_with_providers(main)
	
	l = Lister()
	cp.tree.mount(l, '/', cp_app_config)
	cp._global_conf_alias.update(cp_global_config)
	for reld in os.listdir(directory):
		d = os.path.join(directory, reld)
		if not os.path.isdir(d): continue
		try:
			prov = prober(d)
		except OSError:
			continue
		if len(prov) == 0: continue
		s = SessionServer(prov)
		l.services.append(reld)
		cp.tree.mount(s, "/"+reld)
	
	if hasattr(cp.engine, "signal_handler"):
		cp.engine.signal_handler.subscribe()
	if hasattr(cp.engine, "console_control_handler"):
		cp.engine.console_control_handler.subscribe()
	cp.engine.start()
	cp.engine.block()

def run_with_providers(providers):
	cp.quickstart(RootServer(providers), '/',
		config={'global': cp_global_config})

if __name__ == '__main__':
	import providers
	import json
	import sys
	resources = json.load(open(sys.argv[1]))
	provs = providers.passthrough_providers(resources,
			os.path.dirname(sys.argv[1]))
	run_with_providers(provs)

