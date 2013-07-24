import mimetypes
from itertools import chain
from copy import copy
import os
import json
import time
from collections import Mapping

def add_content_type_param(ct, param):
	return "%s; %s"%(ct, param)

class FileResult:
	def __init__(self, path):
		self.path = path

class PathProvider(object):
	def __init__(self, mypath, content_type):
		self.mypath = mypath
		self.content_type = content_type
	
	def provides(self):
		return {self.mypath: self.content_type}

	def __call__(self, *path, **kwargs):
		if path[0] != self.mypath:
			return None

		return ({'Content-Type': self.content_type},
			self.handle(**kwargs))
	
	def handle(self, **kwargs):
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
		return FileResult(os.path.abspath(self.filepath))

class AuxProvider(object):
	def __init__(self, provider, *aux_providers):
		self.provider = provider
		for n, p in aux_providers:
			if len(p.provides()) != 1:
				raise ValueError("Aux provider %s (%s) doesn't provide exactly one resource."%(n, p))

		self.aux_providers = aux_providers
	
	def provides(self):
		res = {}
		main = copy(self.provider.provides())
		for n, p in self.aux_providers[::-1]:
			a_res = p.provides()
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

class AnnotationProvider(FileProvider):
	def __init__(self, directory,
			filename="trusas-annotations.jsons",
			content_type="application/vnd.trusas.annotations"):
		super(AnnotationProvider, self).__init__(
			os.path.join(directory, filename),
			content_type=content_type,
			must_be_readable=False)

		if not os.path.exists(self.filepath):
			with open(self.filepath, 'a'):
				pass
	
	def handle(self, **kwargs):
		ret = lambda: super(AnnotationProvider, self).handle()
		if not 'action' in kwargs or kwargs['action'] != 'add':
			return ret()

		if not ('ts' in kwargs and 'text' in kwargs):
			return ret()
		
		with open(self.filepath, 'a') as f:
			annot = [
				{'ts': float(kwargs['ts']), 'added_ts': time.time()},
				{'text': unicode(kwargs['text'])}
				]

			# TODO: Lock the file!
			json.dump(annot, f)
			f.write("\n")
		
		return ret()

def passthrough_providers(resources, basepath=None):
	providers = []
	for name, content_type in resources.iteritems():
		if basepath:
			filepath = os.path.join(basepath, name)
		provider = FileProvider(filepath,
				content_type=content_type,
				provides=name)
		providers.append(provider)
	return providers

