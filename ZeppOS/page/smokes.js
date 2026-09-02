import { createWidget, widget, prop, align, text_style } from '@zos/ui'
import { log } from '@zos/utils'
import { BasePage } from '@zeppos/zml/base-page'
import { statSync, writeFileSync, readFileSync } from '@zos/fs'

const logger = log.getLogger('dayone-orbit-smokes')

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
        logger.info('smokes page build invoked')
        let total = 0
        const self = this
        
        const totalText = createWidget(widget.TEXT, {
          x: 0,
          y: 80,
          w: 390,
          h: 60,
          color: 0xffaa00,
          text_size: 40,
          align_h: align.CENTER_H,
          align_v: align.CENTER_V,
          text: 'Total: 0'
        })

        const logHabit = (amount, type) => {
          const accessToken = loadFileStr('token.txt')
          const userId = loadFileStr('userid.txt')
          if (!accessToken || !userId) return

          total += amount
          totalText.setProperty(prop.TEXT, `Total: ${total}`)

          self.request({
            method: 'LOG_HABIT',
            params: {
              access_token: accessToken,
              user_id: userId,
              habit_type: 'smokes',
              value: amount,
              unit: 'count',
              metadata: { type: type }
            }
          }).then(res => {
            if (!res || !res.success) {
               logger.error('Failed to log habit', res)
               total -= amount
               totalText.setProperty(prop.TEXT, `Total: ${total}`)
            }
          }).catch(err => {
            logger.error('Network error logging habit', err)
            total -= amount
            totalText.setProperty(prop.TEXT, `Total: ${total}`)
          })
        }

        createWidget(widget.BUTTON, {
          x: 45,
          y: 160,
          w: 300,
          h: 70,
          radius: 35,
          normal_color: 0xff3b30,
          press_color: 0xaa2010,
          text: '+1 Smoke',
          color: 0xffffff,
          text_size: 24,
          click_func: () => {
            logHabit(1, 'Smoke')
          }
        })

        createWidget(widget.BUTTON, {
          x: 45,
          y: 250,
          w: 300,
          h: 70,
          radius: 35,
          normal_color: 0xff9500,
          press_color: 0xb56500,
          text: '+1 Vape',
          color: 0xffffff,
          text_size: 24,
          click_func: () => {
            logHabit(1, 'Vape')
          }
        })
        
        const fetchTodayTotal = () => {
          const accessToken = loadFileStr('token.txt')
          if (!accessToken) return
          
          self.request({
            method: 'GET_HABITS_TODAY',
            params: {
              access_token: accessToken,
              habit_type: 'smokes',
            }
          }).then(res => {
            if (res && res.success && res.data) {
              total = res.data.total || 0
              totalText.setProperty(prop.TEXT, `Total: ${total}`)
            }
          }).catch(err => {
            logger.error('Failed to fetch total', err)
          })
        }

        fetchTodayTotal()
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
