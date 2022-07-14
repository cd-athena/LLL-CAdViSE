const express = require('express')
const fs = require('fs')
const app = express()
const AWS = require('aws-sdk')
AWS.config.update({ region: 'eu-central-1' })
const dynamoDb = new AWS.DynamoDB.DocumentClient()
const axios = require('axios')
const { v4: uuidv4 } = require('uuid')
const { serverIp, id } = require('./config.json')

app.get('/favicon.ico', async (request, response) => {
  response.send()
})

app.get('/player/:playerName/:fileName', async (request, response) => {
  const { playerName, fileName } = request.params
  fs.createReadStream('player/' + playerName + '/' + fileName).pipe(response)
})

app.get('/:title/:fileName', async (request, response) => {
  const { title, fileName } = request.params
  const { playerABR } = request.query
  const BASEURL = 'http://' + serverIp + '/'

  try {
    await log(playerABR, 'requesting', title, fileName)
  } catch (error) {
    return response.send('Failed to record the log: ' + JSON.stringify(error))
  }

  const axiosParams = {
    method: 'get',
    url: BASEURL + title + '/' + fileName
  }

  if (!fileName.includes('mpd') && !fileName.includes('m3u8')) {
    axiosParams.responseType = 'stream'
  }

  axios(axiosParams).then((serverResponse) => {
    if (fileName.includes('mpd') || fileName.includes('m3u8')) {
      const manifest = serverResponse.data.toString().replace(/.m4s/g, '.m4s?playerABR=' + playerABR).replace(/.m3u8/g, '.m3u8?playerABR=' + playerABR)
      response.send(manifest)
    } else {
      serverResponse.data.pipe(response)
    }
  }).catch(console.error)
})

app.get('/log/:title/:eventName', async (request, response) => {
  const { title, eventName } = request.params
  const { playerABR } = request.query

  try {
    await log(playerABR, 'event', title, eventName)
  } catch (error) {
    return response.send('Failed to record the log: ' + JSON.stringify(error))
  }

  response.send('ok')
})

app.listen(80, () => {
  console.log('Listening on port 80')
})

const log = async (playerABR, action, title, name) => {
  return dynamoDb.put({
    TableName: 'ppt-logs',
    Item: {
      id: uuidv4(),
      experimentId: id,
      time: (new Date()).toISOString(),
      playerABR,
      action,
      title,
      name
    }
  }).promise()
}
