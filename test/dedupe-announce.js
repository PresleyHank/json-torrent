var fs = require('fs')
var parseTorrentFile = require('../')
var test = require('tape')

var leavesDuplicateTracker = fs.readFileSync(__dirname + '/torrents/leaves-duplicate-tracker.torrent')

var expectedAnnounce = [
  'http://tracker.example.com/announce'
]

test('dedupe announce list', function (t) {
  t.deepEqual(parseTorrentFile(leavesDuplicateTracker).announce, expectedAnnounce)
  t.end()
})
