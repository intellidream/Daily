import { createWidget, widget, prop, align, text_style } from '@zos/ui'
import { log } from '@zos/utils'
import { HeartRate, Sleep } from '@zos/sensor'
const logger = log.getLogger('dayone-orbit')
const appId = 1000001

Page({
  build() {
    logger.info('page build invoked')
    
    // Generate a random 6 digit pin
    const pin = Math.floor(100000 + Math.random() * 900000).toString()

    const text = createWidget(widget.TEXT, {
      x: 0,
      y: 80,
      w: 390,
      h: 80,
      color: 0xffffff,
      text_size: 24,
      align_h: align.CENTER_H,
      align_v: align.CENTER_V,
      text_style: text_style.WRAP,
      text: 'DayOne Orbit\nPairing PIN'
    })

    const pinText = createWidget(widget.TEXT, {
      x: 0,
      y: 180,
      w: 390,
      h: 100,
      color: 0x00ff00,
      text_size: 48,
      align_h: align.CENTER_H,
      align_v: align.CENTER_V,
      text: pin
    })

    const statusText = createWidget(widget.TEXT, {
      x: 0,
      y: 280,
      w: 390,
      h: 50,
      color: 0xaaaaaa,
      text_size: 16,
      align_h: align.CENTER_H,
      align_v: align.CENTER_V,
      text: 'Waiting for Desktop...'
    })

    // Request App Side Service to send PIN to Supabase
    /*
    messageBuilder.request({
      method: 'PAIR_WATCH',
      params: { pin }
    })
    .then(data => {
      logger.info('Successfully paired! Token data:', data)
      statusText.setProperty(prop.MORE, { text: 'Paired! Syncing...', color: 0x00ff00 })
      
      // Initialize Sensors after pairing
      // const hr = new HeartRate()
      // const sleep = new Sleep()
      
      // Example of grabbing latest reading
      // logger.info('Current HR:', hr.getLast())
      // logger.info('Sleep Stage:', sleep.getStageConstant())
      
      // TODO: Save tokens to @zos/fs and start background sync interval
    })
    .catch(res => {
      logger.error('Pairing failed:', res)
    })
    */
  },
  onInit() {
    logger.info('page onInit invoked')
    // messageBuilder.connect()
  },
  onDestroy() {
    logger.info('page onDestroy invoked')
    // messageBuilder.disConnect()
  }
})
