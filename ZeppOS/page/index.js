import { createWidget, widget, prop, align, text_style } from '@zos/ui'
import { log } from '@zos/utils'
import { setTimeout, setInterval, clearInterval } from '@zos/timer'
import { BasePage } from '@zeppos/zml/base-page'
import { push, exit } from '@zos/router'
import { statSync, writeFileSync, readFileSync } from '@zos/fs'

const logger = log.getLogger('dayone-orbit')

function saveFileStr(filename, dataStr) {
  try {
    writeFileSync({
      path: filename,
      data: dataStr,
      options: { encoding: 'utf8' }
    })
  } catch(e) {
    logger.error('saveFileStr error', e)
  }
}

function loadFileStr(filename) {
  try {
    const stat = statSync({ path: filename })
    if (stat) {
      return readFileSync({ path: filename, options: { encoding: 'utf8' } })
    }
  } catch(e) {}
  return ''
}

Page(
  BasePage({
    build() {
      try {
        logger.info('page build invoked')
        
        let accessToken = loadFileStr('token.txt')
        
        if (accessToken) {
          // --- MAIN MENU ---
          createWidget(widget.TEXT, {
            x: 0,
            y: 40,
            w: 390,
            h: 60,
            color: 0xffffff,
            text_size: 28,
            align_h: align.CENTER_H,
            align_v: align.CENTER_V,
            text: 'DayOne Orbit'
          })

          createWidget(widget.BUTTON, {
            x: 45,
            y: 120,
            w: 300,
            h: 80,
            radius: 40,
            normal_color: 0x1c82ff,
            press_color: 0x0a5bc4,
            text: '💧 Bubbles',
            color: 0xffffff,
            text_size: 24,
            click_func: () => {
              push({ url: 'page/bubbles' })
            }
          })

          createWidget(widget.BUTTON, {
            x: 45,
            y: 220,
            w: 300,
            h: 80,
            radius: 40,
            normal_color: 0xff453a,
            press_color: 0xc92b22,
            text: '🚬 Smokes',
            color: 0xffffff,
            text_size: 24,
            click_func: () => {
              push({ url: 'page/smokes' })
            }
          })

          createWidget(widget.BUTTON, {
            x: 45,
            y: 350,
            w: 300,
            h: 50,
            radius: 25,
            normal_color: 0x333333,
            press_color: 0x111111,
            text: '⚙️ Unpair',
            color: 0xaaaaaa,
            text_size: 20,
            click_func: () => {
              saveFileStr('token.txt', '')
              saveFileStr('userid.txt', '')
              exit()
            }
          })

        } else {
          // --- PAIRING UI ---
          const pin = Math.floor(100000 + Math.random() * 900000).toString()

          createWidget(widget.TEXT, {
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

          createWidget(widget.TEXT, {
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

          setTimeout(() => {
            statusText.setProperty(prop.TEXT, 'Sending to Phone...')
            
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
              const maxAttempts = 60;
              
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
                        
                        saveFileStr('token.txt', data[0].access_token)
                        if (data[0].user_id) {
                          saveFileStr('userid.txt', data[0].user_id)
                        }

                        setTimeout(() => {
                           exit()
                        }, 2000)
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
        }
      } catch (fatalErr) {
        createWidget(widget.TEXT, {
          x: 0,
          y: 0,
          w: 390,
          h: 400,
          color: 0xff0000,
          text_size: 20,
          align_h: align.CENTER_H,
          align_v: align.CENTER_V,
          text_style: text_style.WRAP,
          text: fatalErr ? fatalErr.toString() : 'Unknown Build Error'
        })
      }
    },
    
    onInit() {},
    onDestroy() {}
  })
)
