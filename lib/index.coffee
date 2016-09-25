_ = require 'lodash'
bencode = require 'bencode'
iconv = require 'iconv-lite'
sha1 = require 'simple-sha1'

HEX_ENCODED_FIELDS = require './hex-encoded-fields'

MOVE_FIELD_FROM_INFO = [
  'files'
  'name'
  'piece length'
  'pieces'
  'private'
]

# fields that we add to denote formatting
NON_DATA_FIELDS = [
  'infoHash'
  'usesDuplicateUtf8NameKey'
  'usesDuplicateUtf8PathKey'
  'usesExtraneousFilesArray'
]

# announce-list is also renamed, but it's merged with the announce field, so
# we can't do a straight rename
FIELD_RENAME_MAP =
  created: 'creation date'
  createdBy: 'created by'
  pieceLength: 'piece length'
  urlList: 'url-list'

###*
 * Parse a torrent. Throws an exception if the torrent is missing required
   fields.
 * @param  {Buffer} torrent
 * @return {Object} Parsed torrent
###
decode = (torrent) ->
  if not Buffer.isBuffer(torrent)
    throw new Error('Torrent is not a Buffer')

  torrent = bencode.decode(torrent)

  # sanity check
  ensure torrent.info, 'info'
  ensure torrent.info.name, 'info.name'
  ensure torrent.info['piece length'], 'info[\'piece length\']'
  ensure torrent.info.pieces, 'info.pieces'

  if torrent.info.files
    torrent.info.files.forEach (file, i) ->
      ensure typeof file.length is 'number', "info.files[#{i}].length"
      ensure file.path, "info.files[#{i}].path"
      return
  else
    ensure typeof torrent.info.length is 'number', 'info.length'

  torrent.infoHash = sha1.sync(bencode.encode(torrent.info))

  # figure out the encoding first
  if Buffer.isBuffer(torrent.encoding)
    torrent.encoding = torrent.encoding.toString()

  torrentEncoding = torrent.encoding or 'utf8'

  torrent = mapValuesRecursive(torrent, (value, key, fullPath) ->
    if Buffer.isBuffer(value)
      encoding = (
        if fullPath[-1...][0] is 'path.utf-8'
          'utf8'
        else
          torrentEncoding
      )
      decodeStringBuffer(value, encoding, key)
    else
      value
  )

  # announce and announce-list will be missing if metadata fetched via
  # ut_metadata
  torrent.announce = (
    if torrent['announce-list'] and torrent['announce-list'].length
      torrent['announce-list']
    else if torrent.announce
      [torrent.announce]
    else
      []
  ).map((value) ->
    # selectively flatten announce-list so the most common case (each tier
    # having 1 tracker) results in an unnested list.
    if value.length is 1 then value[0] else value
  )
  delete torrent['announce-list']

  torrentLength = torrent.info.length
  delete torrent.info.length

  for key in MOVE_FIELD_FROM_INFO
    if torrent[key]?
      throw new Error("Torrent has disallowed key #{key} (outside of info)")
    if torrent.info[key]?
      torrent[key] = torrent.info[key]
      delete torrent.info[key]

  for newKey, key of FIELD_RENAME_MAP
    if torrent[newKey]?
      throw new Error("Torrent has disallowed key #{newKey}")
    moveKey(torrent, key, newKey)

  if torrent.info['name.utf-8']? and torrent.info['name.utf-8'] is torrent.name
    torrent.usesDuplicateUtf8NameKey = true
    delete torrent.info['name.utf-8']

  if Object.keys(torrent.info).length is 0
    delete torrent.info

  if torrent.files
    torrent.files = torrent.files.map((file, i) ->
      # actually, we should loop through the whole thing and decide if all the
      # keys are duplicates first
      if i isnt 0 and file['path.utf-8']? isnt torrent.usesDuplicateUtf8PathKey?
        # all of the earlier keys up to this point had path.utf-8 or all of the
        # earlier keys up to this point didn't have path.utf-8
        throw new Error("Torrent has mix between path.utf-8 and regular path
        keys")

      if file['path.utf-8']?
        if _.isEqual(file.path, file['path.utf-8'])
          # we set usesDuplicateUtf8PathKey, so we can add it back during encode
          # by copying the regular path key
          torrent.usesDuplicateUtf8PathKey = true
          delete file['path.utf-8']
        else
          throw new Error("Torrent has unequal path keys... implement this")

        if not file.path?
          throw new Error("Torrent has no regular path key")

      file.path = joinPathArray(file.path)
      return file
    )
    if torrent.files.length is 1
      # uTorrent does this, and we need to pay attention to it because it will
      # break the infoHash & throw an error if we normalize the files array
      torrent.usesExtraneousFilesArray = true
  else
    torrent.files = [
      path: torrent.name
      length: torrentLength
    ]

  if torrent.private?
    if torrent.private in [0, 1]
      torrent.private = Boolean(torrent.private)
    else
      throw new Error("Bad value for field 'private': #{torrent.private}")

  torrent.pieces = splitPieces(torrent.pieces)
  return torrent

###*
 * Convert a parsed torrent object back into a .torrent file buffer.
 * @param {Object} parsed Parsed torrent
 * @return {Buffer}
###
encode = (parsed, skipInfoHashCheck = false) ->
  parsed = _.cloneDeep(parsed) # so we can mutate it freely
  parsed.info ?= {}
  parsed.info.length = parsed.files.reduce(((l, file) -> l + file.length), 0)

  if parsed.files.length > 1 or parsed.usesExtraneousFilesArray
    for file in parsed.files
      file.path = file.path.split('/')
      if parsed.usesDuplicateUtf8PathKey
        file['path.utf-8'] = file.path
    delete parsed.info.length
  else
    delete parsed.files

  flatAnnounceList = _.flattenDeep(parsed.announce)
  if flatAnnounceList.length > 1
    # Only add an announce-list if the "multiple trackers" feature (introduced
    # in BEP12) is being used. This reduces the size of the torret file.
    parsed['announce-list'] = parsed.announce.map((url) ->
      # unflatten announce-list
      if Array.isArray(url) then url else [url]
    )

  if flatAnnounceList.length isnt 0
    parsed.announce = flatAnnounceList[0]
  else
    delete parsed.announce

  parsed.pieces = parsed.pieces.join('')
  parsed = mapValuesRecursive(parsed, (value, key, fullPath) ->
    if key in HEX_ENCODED_FIELDS
      new Buffer(value, 'hex')
    else if typeof value is 'string'
      encoding = (
        if fullPath[-1...][0] is 'path.utf-8'
          'utf8'
        else
          parsed.encoding or 'utf8'
      )
      encodeStringBuffer(value, encoding, key)
    else
      value
  )

  for key, newKey of FIELD_RENAME_MAP
    if parsed[newKey]?
      throw new Error("Torrent has disallowed key #{newKey}")
    if parsed[key]?
      parsed[newKey] = parsed[key]
      delete parsed[key]

  for key in MOVE_FIELD_FROM_INFO
    if parsed.info[key]?
      throw new Error("Torrent has key info.#{key} (should be outside of info)")
    if parsed[key]?
      parsed.info[key] = parsed[key]
      delete parsed[key]

  if parsed.usesDuplicateUtf8NameKey
    parsed.info['name.utf-8'] = parsed.info.name

  # make sure that the resulting infoHash matches the infoHash field
  if not skipInfoHashCheck and
     parsed.infoHash isnt sha1.sync(bencode.encode(parsed.info))
    throw new Error("Provided infoHash doesn't match result")

  for key in NON_DATA_FIELDS
    delete parsed[key]

  bencode.encode parsed

decodeStringBuffer = (buf, encoding, key) ->
  if key in HEX_ENCODED_FIELDS
    buf.toString('hex') # hex always works
  else
    iconv.decode(buf, encoding)

encodeStringBuffer = (buf, encoding, key) ->
  if key in HEX_ENCODED_FIELDS
    new Buffer(value, 'hex')
  else
    iconv.encode(buf, encoding)

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

ensure = (bool, fieldName) ->
  if not bool
    throw new Error('Torrent is missing required field: ' + fieldName)
  return

mapValuesRecursive = (obj, mapFn, fullPath = []) ->
  fn = if Array.isArray(obj) then _.map else _.mapValues
  fn(obj, (value, key) ->
    if Array.isArray(value) or _.isPlainObject(value)
      mapValuesRecursive(value, mapFn, fullPath.concat(key))
    else
      mapFn(value, key, fullPath)
  )

module.exports = {decode, encode}
