import simplejson
from base64 import b64encode

try:
	import numpy
	def isnumpyarray(v): return isinstance(v, numpy.ndarray)
except ImportError:
	def isnumpyarray(v): False
	

def _to_nulls(lst):
	# Hack to convert NaNs and Infs to JSON nulls
	if not isinstance(lst, list):
		return lst
	for i in range(len(lst)):
		if isinstance(lst[i], list):
			_to_nulls(lst[i])
			continue
		if lst[i] != lst[i]:
			lst[i] = None
	return lst
	

def object_mangler(v):
	if hasattr(v, 'isoformat'):
		return v.isoformat()
	if hasattr(v, 'tolist'):
		return _to_nulls(v.tolist())
	raise TypeError("Don't know how to serialize "+repr(v))

def _iterable(item):
	return isinstance(item, list) or isinstance(item, dict)

def _pathiter(item):
	if isinstance(item, list):
		return enumerate(item)
	if isinstance(item, dict):
		return item.iteritems()

def _encode_arrays(obj, mangled=None, path=None, root=None):
	if mangled is None:
		mangled = []
		path = []
		root = obj
	
	if isnumpyarray(obj):
		# The root is a numpy array
		mangled.append(([], str(root.dtype)))
		root = b64encode(numpy.getbuffer(root))


	if not _iterable(obj): return root, mangled
	
	for i, v in _pathiter(obj):
		if isnumpyarray(v):
			mangled.append((path+[i], str(v.dtype)))
			obj[i] = b64encode(numpy.getbuffer(v))
		elif _iterable(v):
			_encode_arrays(v, mangled, path+[i], root)

	return root, mangled
	
		

def dump(*args, **kwargs):
	kwargs['default'] = object_mangler
	return simplejson.dump(*args, default=object_mangler)

def dumps(*args, **kwargs):
	kwargs['default'] = object_mangler
	return simplejson.dumps(*args, default=object_mangler)

def result(obj, **kwargs):
	obj, mangling = _encode_arrays(obj)
	ct = "application/json"
	if mangling:
		ct += ";trusas_mangling="+dumps(mangling)

	return ({'Content-Type': ct}, dumps(obj, **kwargs))

