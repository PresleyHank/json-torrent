bencode = require 'bencode'
fs = require 'fs'
should = require 'should'

bitloveParsed = require './torrents/bitlove-intro.json'
leavesMagnetParsed = require './torrents/leaves-magnet.json'
leavesParsed = require './torrents/leaves.json'
numbersParsed = require './torrents/numbers.json'
{decode, encode} = require '../lib'

leavesDuplicateTracker = fs.readFileSync(
  './test/torrents/leaves-duplicate-tracker.torrent'
)
leavesAnnounceList = fs.readFileSync(
  './test/torrents/leaves-empty-announce-list.torrent'
)
leavesEmptyUrlList = fs.readFileSync(
  './test/torrents/leaves-empty-url-list.torrent'
)
bitloveIntro = fs.readFileSync(
  './test/torrents/bitlove-intro.torrent'
)
leavesUrlList = fs.readFileSync(
  './test/torrents/leaves-url-list.torrent'
)
leavesMetadata = fs.readFileSync(
  './test/torrents/leaves-metadata.torrent'
)
numbers = fs.readFileSync(
  './test/torrents/numbers.torrent'
)
leaves = fs.readFileSync(
  './test/torrents/leaves.torrent'
)

describe 'decode', ->
  it 'should parse a single file torrent', ->
    should.deepEqual decode(leaves), leavesParsed

  it 'should parse a "torrent" from magnet metadata protocol', ->
    should.deepEqual(
      decode(leavesMetadata)
      leavesMagnetParsed
    )

  it 'should parse a multiple file torrent', ->
    should.deepEqual decode(numbers), numbersParsed

  it.skip 'should parse a torrent from object', ->
    torrent = bencode.decode(numbers)
    should.deepEqual decode(torrent), numbersParsed

  it 'should throw an error when torrent file is missing `name` field', ->
    ( -> decode(fixtures.corrupt.torrent)).should.throw(Error)

describe 'announce-list', ->
  it 'should not dedupe announce list', ->
    # the JSON should be an accurate representation of the torrent contents, not
    # normalized
    should.deepEqual(
      decode(leavesDuplicateTracker).announce,
      [
        'http://tracker.example.com/announce'
        'http://tracker.example.com/announce'
        'http://tracker.example.com/announce'
      ]
    )

  it 'should parse torrent with empty announce-list', ->
    should.deepEqual(
      decode(leavesAnnounceList).announce,
      ['udp://tracker.publicbt.com:80/announce']
    )

  it 'should parse torrent with no announce-list', ->
    should.deepEqual decode(bitloveIntro), bitloveParsed

describe 'url-list', ->
  it 'should parse empty url-list', ->
    torrent = decode(leavesEmptyUrlList)
    should.deepEqual torrent.urlList, []

  it 'parse url-list for webseed support', ->
    torrent = decode(leavesUrlList)
    should.deepEqual(
      torrent.urlList,
      ['http://www2.hn.psu.edu/faculty/jmanis/whitman/leaves-of-grass6x9.pdf']
    )

  it 'encode url-list for webseed support', ->
    parsedTorrent = decode(leavesUrlList)
    buf = encode(parsedTorrent)
    doubleParsedTorrent = decode(buf)
    should.deepEqual(
      doubleParsedTorrent.urlList,
      ['http://www2.hn.psu.edu/faculty/jmanis/whitman/leaves-of-grass6x9.pdf']
    )

describe 'encode', ->
  it 'should encode', ->
    parsedTorrent = decode(leaves)
    buf = encode(parsedTorrent)
    doubleParsedTorrent = decode(buf)
    should.deepEqual doubleParsedTorrent, parsedTorrent

  it 'should encode w/ comment field', ->
    parsedTorrent = decode(leaves)
    parsedTorrent.comment = 'hi there!'
    buf = encode(parsedTorrent)
    doubleParsedTorrent = decode(buf)
    should.deepEqual doubleParsedTorrent, parsedTorrent
