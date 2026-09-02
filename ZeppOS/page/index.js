import { createWidget, widget, prop, align, text_style } from '@zos/ui'
import { log } from '@zos/utils'
import { HeartRate, Sleep } from '@zos/sensor'
import { setTimeout, setInterval, clearInterval } from '@zos/timer'
import { BasePage } from '@zeppos/zml/base-page'

const logger = log.getLogger('dayone-orbit')
const appId = 1000001
const SUPABASE_URL = 'https://akkfouifxztnfwwiclwg.supabase.co'
const SUPABASE_ANON_KEY = 'sb_publishable_6FzrRSdmsH4arDhZS09PSQ_QK_I31DG'

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

      // Wait 2.5 seconds for BLE network proxy to connect to Zepp App
      setTimeout(() => {
        statusText.setProperty(prop.TEXT, 'Sending to Phone...')
        
        // 1. Send the PIN to Supabase using ZML proxy (custom method)
        this.request({
          method: 'PAIR_WATCH',
          params: { pin }
        })
        .then(response => {
          if (!response || !response.success) {
            statusText.setProperty(prop.TEXT, 'API Error (Phone)')
            statusText.setProperty(prop.COLOR, 0xff0000)
            return
          }

          statusText.setProperty(prop.TEXT, 'Waiting for PC...')
          
          let attempts = 0;
          const maxAttempts = 60; // 3 minutes total
          
          const pollTimer = setInterval(() => {
            this.request({
              method: 'POLL_WATCH',
              params: { pin }
            }).then(pollRes => {
              try {
                if (pollRes && pollRes.success && pollRes.data) {
                  const data = pollRes.data;
                  if (data.length > 0 && data[0].claimed === true && data[0].access_token) {
                    clearInterval(pollTimer)
                    statusText.setProperty(prop.TEXT, 'Paired Successfully!')
                    statusText.setProperty(prop.COLOR, 0x00ff00)
                    logger.info('Received Access Token:', data[0].access_token.substring(0, 20) + '...')
                  } else {
                    attempts++
                    if (attempts >= maxAttempts) {
                      clearInterval(pollTimer)
                      statusText.setProperty(prop.TEXT, 'Timeout. Restart App.')
                      statusText.setProperty(prop.COLOR, 0xff0000)
                    }
                  }
                }
              } catch (e) {
                logger.error('Poll parse error', e)
              }
            }).catch(e => {
              logger.error('Poll network error', e)
            })
          }, 3000)
          
        })
        .catch(err => {
          logger.error('POST network failed:', err)
          statusText.setProperty(prop.TEXT, `Phone proxy failed!`)
          statusText.setProperty(prop.COLOR, 0xff0000)
        })
      }, 3000)
    },
    onInit() {
      logger.info('page onInit invoked')
    },
    onDestroy() {
      logger.info('page onDestroy invoked')
    }
  })
)
