_ = require 'lodash'
iconv = require 'iconv-lite'

HEX_ENCODED_FIELDS = require './hex-encoded-fields'

decodeStringBuffer = (buf, encoding, key) ->
  if key in HEX_ENCODED_FIELDS
    buf.toString('hex') # hex always works
  else
    converted = iconv.decode(buf, encoding)
    #if not buf.equals(iconv.encode(converted, encoding))
    #  throw new Error("Field '#{key}' with encoding '#{encoding}' contains
    #  unparsable characters: #{converted}")
    converted

encodeStringBuffer = (buf, encoding, key) ->
  if key in HEX_ENCODED_FIELDS
    new Buffer(value, 'hex')
  else
    iconv.encode(buf, encoding)

ensure = (bool, fieldName) ->
  if not bool
    throw new Error('Torrent is missing required field: ' + fieldName)
  return

###*
 * Join path array, while checking to make sure it will be able to be split
   later.
 * @param {Array} pathArray
 * @return {String} The joined path.
###
joinPathArray = (pathArray) ->
  pathArray.map((pathSegment) ->
    pathSegment = pathSegment.toString()
    if '/' in pathSegment then throw new Error(
      "Path separator found in path segment: \"#{pathSegment}\""
    )
    return pathSegment
  ).join('/')

mapValuesRecursive = (obj, mapFn, fullPath = []) ->
  fn = if Array.isArray(obj) then _.map else _.mapValues
  fn(obj, (value, key) ->
    if Array.isArray(value) or _.isPlainObject(value)
      mapValuesRecursive(value, mapFn, fullPath.concat(key))
    else
      mapFn(value, key, fullPath)
  )

moveKey = (obj, oldKey, newKey) ->
  if obj[oldKey]?
    obj[newKey] = obj[oldKey]
    delete obj[oldKey]

splitPieces = (buf) ->
  if buf.length < 40 or buf.length % 40 isnt 0
    throw new Error('Pieces list has incorrect length')
  pieces = []
  i = 0
  while i < buf.length
    pieces.push buf.slice(i, i + 40)
    i += 40
  pieces

module.exports = {
  decodeStringBuffer
  encodeStringBuffer
  ensure
  joinPathArray
  mapValuesRecursive
  moveKey
  splitPieces
}
