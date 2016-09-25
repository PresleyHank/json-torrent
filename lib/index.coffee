_ = require 'lodash'
bencode = require 'bencode'
sha1 = require 'simple-sha1'

{
  decodeStringBuffer
  encodeStringBuffer
  ensure
  joinPathArray
  mapValuesRecursive
  moveKey
  splitPieces
} = require './util'

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
  'usesExtraneousLengthKey'
  'usesOnlyUtf8PathKey'
  'usesSingleItemUrlListArray'
]

# announce-list is also renamed, but it's merged with the announce field, so
# we can't do a straight rename
FIELD_RENAME_MAP =
  created: 'creation date'
  createdBy: 'created by'
  pieceLength: 'piece length'
  urlList: 'url-list'

testForDuplicateUtf8PathKey = (files) ->
  # `path.utf-8` and the regular `path` key has to be identical in all objects
  # for us to be able to losslessly remove `path.utf-8`
  for file in files
    if not file.path? or not file['path.utf-8']? or
       not _.isEqual(file.path, file['path.utf-8'])
      return false
  return true

testForOnlyUtf8PathKey = (files) ->
  for file in files
    if file.path? or not file['path.utf-8']? then return false
  return true

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
      for segment, e in file.path
        ensure Buffer.isBuffer(segment), "info.files[#{i}].path[#{e}]"
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

  if torrent.info.files and torrent.info.length?
    # the files array already has a length key for each file, but some torrents
    # include an extra one at info.length, even when a files array is present
    torrent.usesExtraneousLengthKey = true

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

  # all torrents have info keys, so we can safely recreate this
  if Object.keys(torrent.info).length is 0
    delete torrent.info

  # handle url-list (BEP19 / web seeding)
  if Array.isArray(torrent.urlList) and torrent.urlList.length is 1
    # you would expect that `url-list` would be set to a string when only 1 url
    # is provided, so set a flag to note that this isn't the case. this way we
    # can losslessly restore that in `encode`.
    torrent.usesSingleItemUrlListArray = true

  # if there is only 1 url then it will be represented as a string.
  if typeof torrent.urlList is 'string'
    torrent.urlList = [torrent.urlList]

  if torrent.files
    if testForOnlyUtf8PathKey(torrent.files)
      torrent.usesOnlyUtf8PathKey = true
      for file in torrent.files
        file.path = file['path.utf-8']
        delete file['path.utf-8']
    else if testForDuplicateUtf8PathKey(torrent.files)
      # we set usesDuplicateUtf8PathKey, so we can add it back during encode by
      # copying the regular path key
      torrent.usesDuplicateUtf8PathKey = true
      for file in torrent.files
        delete file['path.utf-8']

    for file in torrent.files
      file.path = joinPathArray(file.path)

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
      if parsed.usesOnlyUtf8PathKey
        file['path.utf-8'] = file.path
        delete file.path
      else if parsed.usesDuplicateUtf8PathKey
        file['path.utf-8'] = file.path
    if not parsed.usesExtraneousLengthKey then delete parsed.info.length
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

  if parsed.urlList?.length is 1 and not parsed.usesSingleItemUrlListArray
    parsed.urlList = parsed.urlList[0]

  parsed.pieces = parsed.pieces.join('')

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

  parsed = mapValuesRecursive(parsed, (value, key, fullPath) ->
    if key is 'infoHash'
      value # don't touch this key
    else if key in HEX_ENCODED_FIELDS
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

  # make sure that the resulting infoHash matches the infoHash field
  if not skipInfoHashCheck and
     parsed.infoHash isnt sha1.sync(bencode.encode(parsed.info))
    throw new Error("Provided infoHash doesn't match result")

  for key in NON_DATA_FIELDS
    delete parsed[key]

  bencode.encode parsed

module.exports = {decode, encode}
