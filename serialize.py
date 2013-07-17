import simplejson

def object_mangler(v):
	if hasattr(v, 'isoformat'):
		return v.isoformat()
	raise TypeError("Don't know how to serialize "+repr(v))

def dump(*args, **kwargs):
	kwargs['default'] = object_mangler
	return simplejson.dump(*args, default=object_mangler)

def dumps(*args, **kwargs):
	kwargs['default'] = object_mangler
	return simplejson.dumps(*args, default=object_mangler)

