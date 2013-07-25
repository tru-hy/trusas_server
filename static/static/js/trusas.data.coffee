`// From https://developer.mozilla.org/en-US/docs/Web/JavaScript/Base64_encoding_and_decoding
function b64ToUint6 (nChr) {

  return nChr > 64 && nChr < 91 ?
      nChr - 65
    : nChr > 96 && nChr < 123 ?
      nChr - 71
    : nChr > 47 && nChr < 58 ?
      nChr + 4
    : nChr === 43 ?
      62
    : nChr === 47 ?
      63
    :
      0;

}


function base64DecToArr (sBase64, nBlocksSize) {
  var
    sB64Enc = sBase64.replace(/[^A-Za-z0-9\+\/]/g, ""), nInLen = sB64Enc.length,
    nOutLen = nBlocksSize ? Math.ceil((nInLen * 3 + 1 >> 2) / nBlocksSize) * nBlocksSize : nInLen * 3 + 1 >> 2, taBytes = new Uint8Array(nOutLen);

  for (var nMod3, nMod4, nUint24 = 0, nOutIdx = 0, nInIdx = 0; nInIdx < nInLen; nInIdx++) {
    nMod4 = nInIdx & 3;
    nUint24 |= b64ToUint6(sB64Enc.charCodeAt(nInIdx)) << 18 - 6 * nMod4;
    if (nMod4 === 3 || nInLen - nInIdx === 1) {
      for (nMod3 = 0; nMod3 < 3 && nOutIdx < nOutLen; nMod3++, nOutIdx++) {
        taBytes[nOutIdx] = nUint24 >>> (16 >>> nMod3 & 24) & 255;
      }
      nUint24 = 0;

    }
  }

  return taBytes;
}`

typemapping =
	float64: Float64Array
	float32: Float32Array

Trusas.demangle_response = (data, mangling) ->
	for [path, type] in mangling
		if path.length == 0
			return new typemapping[type] base64DecToArr(data).buffer

		obj = data
		for i in path[...-1]
			obj = obj[i]
		i = path[path.length-1]
		obj[i] = new typemapping[type] base64DecToArr(obj[i]).buffer

	return data

Trusas.getJSON = (url, data, success) ->
	promise = $.Deferred()
	$.getJSON url, data, (data, status, hdr) ->
		ct = hdr.getResponseHeader("Content-Type")
		parts = ct.split(';')
		for part in parts[1..]
			[name, value] = part.split('=')
			continue if name != 'trusas_mangling'
			continue if not value
			mangling = JSON.parse(value)
			data = Trusas.demangle_response data, mangling

		promise.resolve data, status, hdr

	return promise
		
		
