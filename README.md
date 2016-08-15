# json-torrent

[![travis](https://img.shields.io/travis/feross/parse-torrent-file/master.svg)](https://travis-ci.org/feross/parse-torrent-file) [![npm](https://img.shields.io/npm/v/parse-torrent-file.svg)](https://npmjs.org/package/parse-torrent-file) [![downloads](https://img.shields.io/npm/dm/parse-torrent-file.svg)](https://npmjs.org/package/parse-torrent-file)

[![Sauce Test Status](https://saucelabs.com/browser-matrix/parse-torrent-file.svg)](https://saucelabs.com/u/parse-torrent-file)

A tool to convert torrent files to and from a JSON representation - designed to make torrent file editing, searching, storage, and analysis easy.

Parse a .torrent file and return an object of keys/values. Works in node and the browser (with [browserify](http://browserify.org/)). The `parsed` torrent object looks like this:

```javascript
{
  "infoHash": "d2474e86c95b19b8bcfdb92bc12c9d44667cfa36",
  "name": "Leaves of Grass by Walt Whitman.epub",
  "encoding": "UTF-8",
  "created": 1375363666,
  "createdBy": "uTorrent/3300",
  "comment": "Torrent downloaded from torrent cache at http://itorrents.org",
  "announce": [
    "http://tracker.example.com/announce"
  ],
  "urlList": [],
  "files": [
    {
      "path": "Leaves of Grass by Walt Whitman.epub",
      "length": 362017
    }
  ],
  "pieceLength": 16384,
  "pieces": [
    "1f9c3f59beec079715ec53324bde8569e4a0b4eb",
    "ec42307d4ce5557b5d3964c5ef55d354cf4a6ecc",
    "7bf1bcaf79d11fa5e0be06593c8faafc0c2ba2cf",
    "76d71c5b01526b23007f9e9929beafc5151e6511",
    "0931a1b44c21bf1e68b9138f90495e690dbc55f5",
    "72e4c2944cbacf26e6b3ae8a7229d88aafa05f61",
    "eaae6abf3f07cb6db9677cc6aded4dd3985e4586",
    "27567fa7639f065f71b18954304aca6366729e0b",
    "4773d77ae80caa96a524804dfe4b9bd3deaef999",
    "c9dd51027467519d5eb2561ae2cc01467de5f643",
    "0a60bcba24797692efa8770d23df0a830d91cb35",
    "b3407a88baa0590dc8c9aa6a120f274367dcd867",
    "e88e8338c572a06e3c801b29f519df532b3e76f6",
    "70cf6aee53107f3d39378483f69cf80fa568b1ea",
    "c53b506159e988d8bc16922d125d77d803d652c3",
    "ca3070c16eed9172ab506d20e522ea3f1ab674b3",
    "f923d76fe8f44ff32e372c3b376564c6fb5f0dbe",
    "52164f03629fd1322636babb2c014b7dae582da4",
    "1363965261e6ce12b43701f0a8c9ed1520a70eba",
    "004400a267765f6d3dd5c7beb5bd3c75f3df2a54",
    "560a61801147fa4ec7cf568e703acb04e5610a4d",
    "56dcc242d03293e9446cf5e457d8eb3d9588fd90",
    "c698de9b0dad92980906c026d8c1408fa08fe4ec"
  ]
}
```

## Install

Full installation instructions [here](https://www.npmjs.com/package/json-torrent/tutorial).

```bash
npm install json-torrent
```

## CLI

We include a CLI with two commands (`encode` & `decode`) that operates over STDIO. Decoded JSON is printed in a single line:

```bash
$ json-torrent decode < ./leaves-of-grass.torrent
{"infoHash":"d2474e86c95b19b8bcfdb92bc12c9d44667cfa36","name":"Leaves of Grass by Walt Whitman.epub","encoding":"UTF-8","created":1375363666,"createdBy":"uTorrent/3300","comment":"Torrent downloaded from torrent cache at http://itorrents.org","announce":["http://tracker.example.com/announce"],"urlList":[],"files":[{"path":"Leaves of Grass by Walt Whitman.epub","length":362017}],"pieceLength":16384,"pieces":["1f9c3f59beec079715ec53324bde8569e4a0b4eb","ec42307d4ce5557b5d3964c5ef55d354cf4a6ecc"...
```

This isn't easy to read, so you should use [jq](https://stedolan.github.io/jq/) when you need coloring & pretty-printing:

```bash
$ json-torrent decode < ./leaves-of-grass.torrent | jq
{
  "infoHash": "d2474e86c95b19b8bcfdb92bc12c9d44667cfa36",
  "name": "Leaves of Grass by Walt Whitman.epub",
  "encoding": "UTF-8",
  "created": 1375363666,
  "createdBy": "uTorrent/3300",
  "comment": "Torrent downloaded from torrent cache at http://itorrents.org"
  ...
}
```

Plus, jq can be used for basic editing, like stripping out extraneous fields:

```bash
json-torrent decode < leaves-of-grass.torrent | jq "del(.comment, .announce)" | json-torrent encode > leaves-of-grass-slim.torrent
```

...Or querying specific fields:

```bash
json-torrent decode < slackware.torrent | jq ".files[].path"
"slackware-12.2-install-dvd.iso"
"slackware-12.2-install-dvd.iso.asc"
"slackware-12.2-install-dvd.iso.md5"
```

## Usage

```javascript
var parseTorrentFile = require('json-torrent')
var torrent = fs.readFileSync('torrents/leaves.torrent')
var parsed

try {
  parsed = parseTorrentFile.decode(torrent)
} catch (e) {
  // the torrent file was corrupt
  console.error(e)
}

console.log(parsed.name) // Prints "Leaves of Grass by Walt Whitman.epub"
```

To convert a parsed torrent back into a .torrent file buffer, call `parseTorrentFile.encode`.

```javascript
var parseTorrentFile = require('json-torrent')

// parse a torrent
var parsed = parseTorrentFile.decode(/* some buffer */)

// convert parsed torrent back to a buffer
var buf = parseTorrentFile.encode(parsed)
```

## Similar Tools

- [parse-torrent-file](https://www.npmjs.com/package/parse-torrent-file), which this tool is based upon. It includes some extra data in the parsed output (like Buffers) and doesn't support lossless serialization as JSON.
- [read-torrent](https://www.npmjs.org/package/read-torrent), the tool that parse-torrent-file was based on, which includes more extra junk, like a dependency upon request and some logic for reading files.
