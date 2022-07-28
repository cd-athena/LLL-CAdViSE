const childProcess = require('child_process')
const pathToFfmpeg = require('ffmpeg-static')
const BufferList = require('bl')
const EventEmitter = require('events')
const fs = require('fs-extra')
const http = require('http')

const ingestPort = 8080
const deliveryPort = 80
const cacheMap = new Map()
const diskCachePath = './dataset'
const diskCacheTimeout = 0 // seconds || 0 for no clean-ups
const addedDelay = 333 // each try happens after 3ms
const retryBeforeNotfound = new Map()

class Cache extends EventEmitter {
  constructor () {
    super()
    this.bufferList = new BufferList()
    this.responses = []
    this.ended = false
  }
}

const send = (response, contentType, filename) => {
  const fileContent = fs.readFileSync(filename)
  response.writeHead(200, {
    'Content-Type': contentType,
    'Access-Control-Allow-Origin': '*'
  })
  response.write(fileContent)
  response.end()
}

const sendChunked = (response, content_type, filename) => {
  const readStream = fs.createReadStream(filename)

  readStream.on('error', _ => {
    if (!retryBeforeNotfound.has(filename)) {
      retryBeforeNotfound.set(filename, addedDelay)
    }
    if (retryBeforeNotfound.get(filename) > 0) {
      retryBeforeNotfound.set(filename, retryBeforeNotfound.get(filename) - 1)
      setTimeout(_ => {
        sendChunkedCached(response, content_type, filename)
      }, 3)
    } else {
      console.log(`404 bad file ${filename}`)
      send404(response)
    }
  })

  readStream.once('readable', _ => {
    response.writeHead(200, {
      'Content-Type': content_type,
      'Transfer-Encoding': 'chunked',
      'Access-Control-Allow-Origin': '*'
    })
    readStream.pipe(response)
  })
}

const sendChunkedCached = (response, contentType, filename) => {
  if (cacheMap.has(filename)) {
    const cache = cacheMap.get(filename)

    response.writeHead(200, {
      'Content-Type': contentType,
      'Transfer-Encoding': 'chunked',
      'Access-Control-Allow-Origin': '*'
    })

    response.write(cache.bufferList.slice())

    if (cache.ended) {
      response.end()
    } else {
      cache.responses.push(response)
      cache.on('data', (chunk) => {
        response.write(chunk)
      })
    }
  } else {
    sendChunked(response, contentType, filename)
  }
}

const send404 = response => {
  response.statusCode = 404
  response.statusMessage = 'Not found'
  response.end()
}

const send500 = response => {
  response.statusCode = 500
  response.statusMessage = 'Internal error'
  response.end()
}

const ingestServer = http.createServer((request, response) => {
  console.log(request.method, request.url)
  if (request.method === 'PUT') {
    const filename = diskCachePath + request.url
    const writeStream = fs.createWriteStream(filename)

    writeStream.on('error', (err) => {
      send500(response)
      throw err
    })

    cacheMap.set(filename, new Cache())

    cacheMap.get(filename).on('end', function () {
      this.ended = true
      const l = this.responses.length
      for (var i = 0; i < l; i++) {
        this.responses[0].end()
        this.responses.shift()
      }
      cacheMap.delete(filename)

      if (request.url.includes('chunk-') && diskCacheTimeout > 0) {
        setTimeout(() => {
          fs.unlinkSync(filename)
        }, diskCacheTimeout * 1000)
      }
    })

    request.on('data', (chunk) => {
      if (!cacheMap.has(filename)) return
      cacheMap.get(filename).bufferList.append(chunk)
      cacheMap.get(filename).emit('data', chunk)
      writeStream.write(chunk)
    })

    request.on('end', () => {
      if (!cacheMap.has(filename)) return
      cacheMap.get(filename).emit('end')
      writeStream.end()
    })
  }
})

const deliveryServer = http.createServer((request, response) => {
  console.log(request.method, request.url)
  if (request.method === 'GET') {
    const suffixIdx = request.url.lastIndexOf('.')
    let suffix = request.url.slice(suffixIdx, request.url.length)
    let filename = diskCachePath + request.url

    if (suffix.includes('?')) {
      suffix = suffix.slice(0, suffix.indexOf('?'))
      filename = diskCachePath + request.url.slice(0, request.url.indexOf('?'))
    }

    switch (suffix) {
      case '.mpd':
        send(response, 'application/dash+xml', filename)
        break
      case '.m3u8':
        send(response, 'application/x-mpegURL', filename)
        break
      case '.m4s':
        sendChunkedCached(response, 'video/iso.segment', filename)
        break
      default:
        console.log('404 bad suffix', suffix)
        send404(response)
        break
    }
  }
})

ingestServer.listen(ingestPort)
deliveryServer.listen(deliveryPort)

console.log(`Listening for ingest on port:   ${ingestPort}`)
console.log(`Listening for delivery on port: ${deliveryPort}`)

const getParams = _ => {
  const streamConfig = JSON.parse(fs.readFileSync('streams.json'))
  const highestResolution = streamConfig[Object.keys(streamConfig)[Object.keys(streamConfig).length - 1]].resolution
  let params = [
    '-hide_banner',
    '-re', '-f', 'lavfi',
    '-i', 'testsrc2=size=' + highestResolution + ':rate=25,' +
    'drawbox=x=0:y=0:w=700:h=50:c=black@.6:t=fill,' +
    'drawtext=x=5:y=5:fontfile=FreeSans.ttf:fontsize=54:fontcolor=white:text=\'CAdViSE\',' +
    'drawtext=x=345:y=5:fontfile=FreeSans.ttf:fontsize=50:fontcolor=white:timecode=\'' + new Date().toTimeString().split(' ')[0].replace(/:/g, '\\:') + '\\:00\':rate=25:tc24hmax=1,' +
    'setparams=field_mode=prog:range=tv:color_primaries=bt709:color_trc=bt709:colorspace=bt709,' +
    'format=yuv420p',
    '-re', '-f', 'lavfi',
    '-i', 'sine=f=1000:r=48000:samples_per_frame=\'st(0,mod(n,5)); 1602-not(not(eq(ld(0),1)+eq(ld(0),3)))\'',
    '-shortest',
    '-fflags', 'genpts'
  ]

  let filterComplexValues = ''
  for (const streamsKey in streamConfig) {
    const stream = streamConfig[streamsKey]
    const streamIndex = Object.keys(streamConfig).indexOf(streamsKey)
    if (streamIndex === 0) {
      params.push('-filter_complex')
    }
    filterComplexValues += '[0:v]drawtext=x=(w-text_w)-5:y=5:fontfile=FreeSans.ttf:fontsize=54:fontcolor=white:text=\'' + stream.text + '\':box=1:boxcolor=black@.6:boxborderw=5,scale=' + stream.resolution + streamsKey
    if (streamIndex + 1 !== Object.keys(streamConfig).length) { // last stream
      filterComplexValues += ';'
    }
  }
  params.push(filterComplexValues)

  for (const streamsKey in streamConfig) {
    params.push('-map')
    params.push(streamsKey)
  }

  params = params.concat([
    '-map', '1:a',
    '-c:v', 'libx264',
    '-preset:v', 'veryfast',
    '-tune', 'zerolatency',
    '-profile:v', 'main'
  ])

  for (const streamsKey in streamConfig) {
    const stream = streamConfig[streamsKey]
    const streamIndex = Object.keys(streamConfig).indexOf(streamsKey)
    params.push('-b:v:' + streamIndex, stream.bitrate)
    params.push('-maxrate:v:' + streamIndex, stream.bitrate)
    params.push('-bufsize:v:' + streamIndex, parseInt(parseInt(stream.bitrate) * 2 / 3).toString())
    params.push('-s:v:' + streamIndex, stream.resolution)
  }

  params = params.concat([
    '-g:v', '100000', '-keyint_min:v', '50000', '-force_key_frames:v', 'expr:gte(t,n_forced*2)',
    '-x264opts', 'no-open-gop=1',
    '-bf', '2', '-b_strategy', '2', '-refs', '1',
    '-rc-lookahead', '24',
    '-export_side_data', 'prft',
    '-field_order', 'progressive', '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-color_range', 'tv',
    '-pix_fmt', 'yuv420p',
    '-c:a', 'aac',
    '-b:a', '128k',
    '-format_options', 'movflags=+cmaf',
    '-live', '1',
    '-update_period', '4',
    '-use_timeline', '0',
    '-use_template', '1',
    '-init_seg_name', '$Bandwidth$-init.$ext$',
    '-media_seg_name', '$Bandwidth$-$Number$.$ext$',
    '-dash_segment_type', 'mp4',
    '-seg_duration', '2',
    '-adaptation_sets', 'id=0,frag_type=duration,frag_duration=1,streams=v ' +
    'id=1,frag_type=duration,frag_duration=1,streams=a',
    '-write_prft', '1',
    '-utc_timing_url', 'https://time.akamai.com?iso&amp;ms',
    '-streaming', '1',
    '-ldash', '1',
    '-lhls', '1',
    '-strict', 'experimental',
    '-target_latency', '5',
    '-min_playback_rate', '0.96',
    '-max_playback_rate', '1.04',
    '-method', 'PUT',
    '-http_persistent', '1',
    '-timeout', '2',
    '-ignore_io_errors', '1',
    '-http_opts', 'chunked_post=1',
  ])

  params.push('http://localhost:' + ingestPort + '/live/manifest.mpd')
  return params
}

const child = childProcess.spawn(pathToFfmpeg, getParams(), {
  stdio: 'pipe'
})

child.on('error', error => {
  console.error(new Error('There was an error spawning FFMPEG:' + error.toString()))
})

child.on('exit', (code, signal) => {
  console.error(new Error(`FFMPEG exited with code ${code} and signal ${signal}`))
})

child.stderr.on('data', data => {
  console.log(data.toString())
  const keywords = new RegExp(/(Error writing trailer|Broken pipe|Failed to resolve hostname|keepalive request failed|Network is unreachable|Operation timed out|Conversion failed!)/g)
  if (keywords.test(data.toString())) {
    child.kill('SIGINT')
    console.error(new Error(data.toString()))
  }
})

child.stdout.on('data', data => {
  console.log(data.toString())
})

const cleanExit = () => {
  child.kill()
  process.exit()
}

process.on('SIGINT', cleanExit)
process.on('SIGTERM', cleanExit)
process.on('exit', cleanExit)
