_ = require 'lodash'
bencode = require 'bencode'
sha1 = require 'simple-sha1'

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

  result = {}
  result.infoHash = sha1.sync(bencode.encode(torrent.info))

  torrent = mapValuesRecursive(torrent, (value, key) ->
    if Buffer.isBuffer(value)
      if key is 'pieces'
        value.toString('hex')
      else
        value.toString()
    else
      value
  )

  result.name = torrent.info.name

  if torrent.encoding?
    result.encoding = torrent.encoding

  if torrent.info.private?
    result.private = !!torrent.info.private

  if torrent['creation date']?
    result.created = torrent['creation date']

  if torrent['created by']?
    result.createdBy = torrent['created by']

  if torrent.comment?
    result.comment = torrent.comment

  # announce and announce-list will be missing if metadata fetched via
  # ut_metadata
  result.announce = (
    if torrent['announce-list'] and torrent['announce-list'].length
      torrent['announce-list']
    else if torrent.announce
      [torrent.announce.toString()]
    else
      []
  ).map((value) ->
    # selectively flatten announce-list so the most common case (each tier
    # having 1 tracker) results in an unnested list.
    if value.length is 1 then value[0] else value
  )

  # handle url-list (BEP19 / web seeding)
  if torrent['url-list']?
    # some clients set url-list to empty string
    result.urlList = (
      if torrent['url-list'].length > 0 then [torrent['url-list']] else []
    ).map((url) ->
      url.toString()
    )

  result.files = (
    if torrent.info.files
      torrent.info.files.map((file, i) ->
        {
          path: joinPathArray(file.path)
          length: file.length
        }
      )
    else
      [
        path: result.name
        length: torrent.info.length
      ]
  )

  result.pieceLength = torrent.info['piece length']
  result.pieces = splitPieces(torrent.info.pieces)
  return result

###*
 * Convert a parsed torrent object back into a .torrent file buffer.
 * @param {Object} parsed Parsed torrent
 * @return {Buffer}
###
encode = (parsed) ->
  torrent = info:
    'piece length': parsed.pieceLength
    length: parsed.files.reduce(((sum, file) -> sum + file.length), 0)
    name: parsed.name
    pieces: new Buffer(parsed.pieces.join(''), 'hex')

  if parsed.private?
    torrent.info.private = parsed.private

  if parsed.files.length > 1
    torrent.info.files = parsed.files
    for file in torrent.info.files
      file.path = file.path.split('/')
    delete torrent.info.length

  flatAnnounceList = _.flattenDeep(parsed.announce)
  if flatAnnounceList.length isnt 0
    torrent.announce = flatAnnounceList[0]
  if flatAnnounceList.length > 1
    # Only add an announce-list if the "multiple trackers" feature (introduced
    # in BEP12) is being used. This reduces the size of the torret file.
    torrent['announce-list'] = parsed.announce.map((url) ->
      # unflatten announce-list
      if Array.isArray(url) then url else [url]
    )

  if parsed.comment then torrent.comment = parsed.comment
  if parsed.created then torrent['creation date'] = parsed.created
  if parsed.createdBy then torrent['created by'] = parsed.createdBy
  if parsed.encoding then torrent.encoding = parsed.encoding
  if parsed.urlList and parsed.urlList.length isnt 0
    torrent['url-list'] = parsed.urlList

  bencode.encode torrent

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
