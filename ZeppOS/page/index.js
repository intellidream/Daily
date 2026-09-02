import { createWidget, widget, prop, align, text_style } from '@zos/ui'
import { log } from '@zos/utils'
import { HeartRate, Sleep } from '@zos/sensor'
import { BasePage } from '@zeppos/zml/base-page'
import { setTimeout } from '@zos/timer'
const logger = log.getLogger('dayone-orbit')
const appId = 1000001

Page(
  BasePage({
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
      text: 'Connecting to phone...'
    })

    // Wait 2 seconds for BLE message channel to establish with Zepp App
    setTimeout(() => {
      statusText.setProperty(prop.TEXT, 'Registering PIN...')
      this.request({
        method: 'PAIR_WATCH',
        params: { pin }
      })
      .then(data => {
        logger.info('Successfully paired! Token data:', data)
        statusText.setProperty(prop.TEXT, 'Paired! Syncing...')
        statusText.setProperty(prop.COLOR, 0x00ff00)
      })
      .catch(res => {
        logger.error('Pairing failed:', res)
        statusText.setProperty(prop.TEXT, 'Failed. Try again.')
        statusText.setProperty(prop.COLOR, 0xff0000)
      })
    }, 2000)
  },
  onInit() {
    logger.info('page onInit invoked')
  },
  onDestroy() {
    logger.info('page onDestroy invoked')
  }
})
)
