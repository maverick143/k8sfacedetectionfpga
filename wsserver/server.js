'use strict'

const msgpack = require('@msgpack/msgpack')

const http = require('http')
const WebSocket = require('ws')
const url = require('url')
const redis = require('redis')
const httpProxy = require('http-proxy')

console.log('Proxying HTTP requests to', process.env.CAMSERVER)
const proxy = httpProxy.createProxyServer({ target: process.env.CAMSERVER })

const server = http.createServer()
const adminWs = new WebSocket.Server({ noServer: true })
const userWs = new WebSocket.Server({ noServer: true })

const redisOptions = { 'host': process.env.REDIS_HOST, 'detect_buffers': true }
const redisClient = redis.createClient(redisOptions)

redisClient.on('error', (err) => {
  console.log('Redis Error ', err)
})

server.on('request', (req, res) => {
  const u = url.parse(req.url, true)
  const pathname = u.pathname
  if (pathname === '/health') {
    res.writeHead(204, {'Content-Type': 'text/html'})
    res.end()
  }
  else {
    console.log('Proxy request', req.method, req.url)
    proxy.web(req, res)
  }
})

const wsUrl = /^\/ws\/(?<type>admins?|user)\/(?<id>[a-f0-9]{32})$/

server.on('upgrade', (request, socket, head) => {
  const u = url.parse(request.url, true)
  const pathname = u.pathname
  const urlMatch = wsUrl.exec(pathname)

  if (urlMatch && urlMatch.groups.type === 'admin') {
    console.log('connection for /admin from', urlMatch.groups.id)
    adminWs.handleUpgrade(request, socket, head, (ws) => {
      ws.client_id = urlMatch.groups.id
      adminWs.emit('connection', ws, request)
    })
  } else if (urlMatch && urlMatch.groups.type === 'admins') {
    console.log('connection for /admins from', urlMatch.groups.id)
    adminWs.handleUpgrade(request, socket, head, (ws) => {
      ws.client_id = urlMatch.groups.id
      ws.cam_publisher = true
      adminWs.emit('connection', ws, request)
    })
  } else if (urlMatch && urlMatch.groups.type === 'user') {
    console.log('connection for /user from', urlMatch.groups.id)
    userWs.handleUpgrade(request, socket, head, (ws) => {
      ws.client_id = urlMatch.groups.id
      userWs.emit('connection', ws, request)
    })
  } else {
    socket.destroy()
  }
})

function noop () {
}

function heartbeat () {
  // Mark a websocket connection as alive
  this.isAlive = true
}

adminWs.on('connection', (ws) => {
  const log = (...args) => {
    console.log(ws.client_id, ...args)
  }
  log('admin WS connection')
  ws.isAlive = true
  ws.on('pong', heartbeat)

  ws.on('message', (data) => {
    let decoded = msgpack.decode(data)
    log('received:', decoded)
    redisClient.publish('campublisher.control', data)
  })

  const subscriber = redisClient.duplicate({ 'return_buffers': true, 'detect_buffers': false })
  subscriber.on('error', (err) => {
    log(`Redis Error:`, err)
  })

  subscriber.on('pmessage', (pattern, channel, message) => {
    if (pattern.toString() === 'clients.frames.*') {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(message)
      }
    }
    if (pattern.toString() === 'clients.detected.*') {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(message)
      }
    }
    if (pattern.toString() === 'clients.faces.*') {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(message.toString())
      }
    }
    if (pattern.toString() === 'campublisher.detected.*') {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(message)
      }
    }
    if (pattern.toString() === 'campublisher.control_changed') {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(message.toString())
      }
    }
  })

  let channels = ['clients.detected.*', 'campublisher.control_changed']
  if ( ws.cam_publisher ) {
    channels.push('campublisher.detected.*')
  }
  subscriber.psubscribe(...channels, (e, r) => {
    log('Subscribed', e && e.toString(), r && r.toString())
  })

  ws.on('close', () => {
    log('Websocket closed')
    subscriber.quit()
  })

  ws.ping(noop)
})

function randomInt (min, max) {
  min = Math.ceil(min)
  max = Math.floor(max)
  return Math.floor(Math.random() * (max - min)) + min //The maximum is exclusive and the minimum is inclusive
}

userWs.on('connection', (ws) => {
  const log = (...args) => {
    console.log(ws.client_id, ...args)
  }

  log('user WS connection')
  ws.isAlive = true
  ws.on('pong', heartbeat)
  const startTime = Date.now()

  const clientIdBuffer = Buffer.from(ws.client_id, 'hex')

  ws.on('message', (data) => {
    if (data instanceof Buffer) {
      const now = Date.now()

      ws.send(JSON.stringify({ 't': 'snap', 'd': 125 }))
      const encoded = msgpack.encode({
        clientId: clientIdBuffer,
        image: data,
        published: now,
        resultTopic: `clients.detected.${ws.client_id}`
      })
      const imageData = Buffer.from(encoded.buffer, encoded.byteOffset, encoded.byteLength)
      redisClient.rpush(['images', imageData], (err, reply) => {
        if (err) {
          log('Redis push error', err, reply)
        }
      })
      // Keep no more than 100 items in queue
      redisClient.ltrim(['images', 0, 10000])
    }
  })

  const subscriber = redisClient.duplicate({ 'return_buffers': true, 'detect_buffers': false })
  subscriber.on('error', (err) => {
    log(`Redis Error:`, err)
  })

  const faceChannel = `clients.faces.${ws.client_id}`

  subscriber.on('message', (channel, message) => {
    if (channel.toString() === faceChannel) {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(message.toString())
      }
    }
  })
  subscriber.subscribe(faceChannel, (e, r) => {
    log('Subscribed', e && e.toString(), r && r.toString())
  })

  ws.on('close', () => {
    log('Websocket closed')
    subscriber.quit()
  })

  ws.ping(noop)
})

const ping = (ws) => {
  if (ws.isAlive === false) {
    console.log('terminate client')
    return ws.terminate()
  }

  ws.isAlive = false
  ws.ping(noop)
}

// Ping all clients every 30 seconds
setInterval(() => {
  userWs.clients.forEach(ping)
  adminWs.clients.forEach(ping)
}, 30000)

server.listen(8080)