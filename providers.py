import mimetypes
from itertools import chain
from copy import copy
import os

def add_content_type_param(ct, param):
	return "%s; %s"%(ct, param)

class PathProvider(object):
	def __init__(self, mypath, content_type):
		self.mypath = mypath
		self.content_type = content_type
		self.provides = {self.mypath: self.content_type}

	def __call__(self, path, **kwargs):
		if path != self.mypath:
			return None

		return ({'Content-Type': self.content_type},
			self.handle(path=path, **kwargs))
	
	def handle(self, path, **kwargs):
		raise NotImplemented

class FileProvider(PathProvider):
	def __init__(self, filepath, content_type=None,
			must_be_readable=True, provides=None):
		if must_be_readable:
			# EAFP as suggested instead of os.access
			with open(filepath, 'r'):
				pass

		self.filepath = filepath
		
		if content_type is None:
			content_type = mimetypes.guess_type(filepath, False)[0]
			if content_type is None:
				content_type = "application/octet-stream"
		
		if provides is None:
			provides = os.path.basename(filepath)
		super(FileProvider, self).__init__(provides, content_type)
	
	def handle(self, **kwargs):
		return os.path.abspath(self.filepath)

class AuxProvider(object):
	def __init__(self, provider, *aux_providers):
		self.provider = provider
		for n, p in aux_providers:
			if len(p.provides) != 1:
				raise ValueError("Aux provider %s (%s) doesn't provide exactly one resource."%(n, p))

		self.aux_providers = aux_providers
	
	@property
	def provides(self):
		res = {}
		main = copy(self.provider.provides)
		for n, p in self.aux_providers[::-1]:
			a_res = p.provides
			res.update(a_res)
			for k in main:
				main[k] += "; %s=%s"%(n, a_res.keys()[0])
		
		res.update(main)
		return res
	
	def __call__(self, *args, **kwargs):
		for p in chain([self.provider], zip(*self.aux_providers)[1]):
			res = p(*args, **kwargs)
			if res is not None:
				return res
