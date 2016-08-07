{ArgumentParser} = require 'argparse'

packageInfo = require '../package'
{decode, encode} = require '../'

argparser = new ArgumentParser(
  addHelp: true
  description: packageInfo.description
  version: packageInfo.version
)
subcommands = argparser.addSubparsers(dest: 'subcommand')

subcommand = subcommands.addParser(
  'decode'
  description: 'Read a torrent from STDIN and print out the parsed JSON'
  addHelp: true
)

subcommand = subcommands.addParser(
  'encode'
  description: 'Read JSON from STDIN and print the torrent file to STDOUT'
  addHelp: true
)

argv = argparser.parseArgs()

buffer = []
process.stdin.on 'readable', ->
  if chunk = process.stdin.read() then buffer.push chunk
  return

process.stdin.on 'end', ->
  buffer = Buffer.concat(buffer)
  if buffer.length is 0 then process.exit(1)
  switch argv.subcommand
    when 'decode'
      try
        torrent = decode(buffer)
      catch error
        console.error error.message
        process.exit(1)

      console.log(JSON.stringify(torrent))
    when 'encode'
      try
        torrent = encode(JSON.parse(buffer.toString()))
      catch error
        console.error error.message
        process.exit(1)

      process.stdout.write(torrent)
  return
