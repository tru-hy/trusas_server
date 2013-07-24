import simplejson

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

def dump(*args, **kwargs):
	kwargs['default'] = object_mangler
	return simplejson.dump(*args, default=object_mangler)

def dumps(*args, **kwargs):
	kwargs['default'] = object_mangler
	return simplejson.dumps(*args, default=object_mangler)

def result(obj, **kwargs):
	return ({'Content-Type': 'application/json'}, dumps(obj, **kwargs))


