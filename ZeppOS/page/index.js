import { createWidget, widget, prop, align, text_style } from '@zos/ui'
import { log } from '@zos/utils'
import { setTimeout, setInterval, clearInterval } from '@zos/timer'
import { BasePage } from '@zeppos/zml/base-page'
import { exit } from '@zos/router'
import { statSync, writeFileSync, readFileSync } from '@zos/fs'
import { setScrollMode, SCROLL_MODE_SWIPER } from '@zos/page'

const logger = log.getLogger('dayone-orbit')

function saveFileStr(filename, dataStr) {
  try { writeFileSync({ path: filename, data: dataStr, options: { encoding: 'utf8' } }) } catch(e) {}
}

function loadFileStr(filename) {
  try {
    const stat = statSync({ path: filename })
    if (stat) return readFileSync({ path: filename, options: { encoding: 'utf8' } })
  } catch(e) {}
  return ''
}

Page(
  BasePage({
    build() {
      try {
        logger.info('page build invoked')
        
        const accessToken = loadFileStr('token.txt')
        const userId = loadFileStr('userid.txt')
        const self = this
        
        if (accessToken) {
          // --- LOADING UI ---
          const loadingText = createWidget(widget.TEXT, {
            x: 0,
            y: 0,
            w: 390,
            h: 450,
            color: 0x00ffff,
            text_size: 24,
            align_h: align.CENTER_H,
            align_v: align.CENTER_V,
            text: 'Loading Orbit...'
          })

          let waterGoal = 2000
          let smokeBaseline = 20
          
          let waterTotal = 0
          let waterVal = 0
          let coffeeVal = 0
          let waterWeek = [0, 0, 0, 0, 0, 0, 0]
          
          let smokeTotal = 0
          let smokeWeek = [0, 0, 0, 0, 0, 0, 0]
          
          let waterHistogram;
          let smokeHistogram;

          const fetchData = () => {
             self.request({
               method: 'GET_PREFS',
               params: { access_token: accessToken, user_id: userId }
             }).then(res => {
               if (res && res.success && res.data) {
                 waterGoal = res.data.water_goal || 2000
                 smokeBaseline = res.data.smokes_baseline || 20
               }
               
               return self.request({
                 method: 'GET_HABITS_TODAY',
                 params: { access_token: accessToken, user_id: userId, habit_type: 'water' }
               })
             }).then(res => {
               if (res && res.success && res.data) {
                 waterTotal = res.data.total || 0
                 waterVal = res.data.waterTotal || 0
                 coffeeVal = res.data.coffeeTotal || 0
               }
               
               return self.request({
                 method: 'GET_HABITS_TODAY',
                 params: { access_token: accessToken, user_id: userId, habit_type: 'smokes' }
               })
             }).then(res => {
               if (res && res.success && res.data) {
                 smokeTotal = res.data.total || 0
               }
               
               return self.request({
                 method: 'GET_HABITS_WEEK',
                 params: { access_token: accessToken, habit_type: 'water' }
               })
             }).then(res => {
               if (res && res.success && res.data) {
                 waterWeek = res.data
               }
               
               return self.request({
                 method: 'GET_HABITS_WEEK',
                 params: { access_token: accessToken, habit_type: 'smokes' }
               })
             }).then(res => {
               if (res && res.success && res.data) {
                 smokeWeek = res.data
               }
               
               loadingText.setProperty(prop.VISIBLE, false)
               buildDashboard()
             }).catch(err => {
               let errMsg = err ? err.toString() : 'Unknown'
               if (err && err.message) errMsg = err.message
               
               loadingText.setProperty(prop.TEXT, 'Err: ' + errMsg.substring(0, 50))
               loadingText.setProperty(prop.COLOR, 0xff0000)
               logger.error('Fetch chain error', err)
               
               createWidget(widget.BUTTON, {
                 x: 45, y: 300, w: 300, h: 60, radius: 30, normal_color: 0x222222, press_color: 0x111111,
                 text: '⚙️ Reset App', color: 0xffffff, text_size: 20,
                 click_func: () => { saveFileStr('token.txt', ''); saveFileStr('userid.txt', ''); exit() }
               })
             })
          }
          
          let waterArc, coffeeArc, waterCenterText
          let smokeArc, smokeCenterText

          const updateWaterUI = () => {
             const goal = Math.max(1, waterGoal)
             let wDegrees = (waterVal / goal) * 360
             if (wDegrees > 360) wDegrees = 360
             let cDegrees = (coffeeVal / goal) * 360
             if (wDegrees + cDegrees > 360) cDegrees = 360 - wDegrees
             
             waterArc.setProperty(prop.MORE, { start_angle: -90, end_angle: -90 + wDegrees })
             coffeeArc.setProperty(prop.MORE, { start_angle: -90 + wDegrees, end_angle: -90 + wDegrees + cDegrees })
             waterCenterText.setProperty(prop.TEXT, `${waterTotal}\n/ ${waterGoal}`)
             
             if (waterHistogram) {
                const maxVal = Math.max(waterGoal, ...waterWeek, 1000)
                waterHistogram.setProperty(prop.UPDATE_DATA, {
                   data_array: waterWeek,
                   data_count: 7,
                   data_min_value: 0,
                   data_max_value: maxVal
                })
             }
          }
          
          const updateSmokeUI = () => {
             const goal = Math.max(1, smokeBaseline)
             const remaining = Math.max(0, goal - smokeTotal)
             
             let color = 0x00ff00
             const ratio = smokeTotal / goal
             if (ratio >= 1.0) color = 0xff0000
             else if (ratio >= 0.5) color = 0xffa500
             
             let sDegrees = (smokeTotal / goal) * 360
             if (sDegrees > 360) sDegrees = 360
             
             smokeArc.setProperty(prop.MORE, { start_angle: -90, end_angle: -90 + sDegrees, color: color })
             smokeCenterText.setProperty(prop.TEXT, `${smokeTotal}\n/ ${goal}`)
             
             if (smokeHistogram) {
                const maxVal = Math.max(smokeBaseline, ...smokeWeek, 10)
                smokeHistogram.setProperty(prop.UPDATE_DATA, {
                   data_array: smokeWeek,
                   data_count: 7,
                   data_min_value: 0,
                   data_max_value: maxVal
                })
             }
             if (ratio >= 1.0) smokeCenterText.setProperty(prop.COLOR, 0xff0000)
             else smokeCenterText.setProperty(prop.COLOR, 0xffffff)
          }

          const logWater = (amount, type) => {
             waterTotal += amount
             waterWeek[6] += amount
             if (type.includes('Coffee')) coffeeVal += amount
             else waterVal += amount
             updateWaterUI()
             
             self.request({
               method: 'LOG_HABIT',
               params: { access_token: accessToken, user_id: userId, habit_type: 'water', value: amount, unit: 'ml', metadata: { drink: type } }
             }).then(res => {
               if (!res || !res.success) {
                  waterTotal -= amount
                  waterWeek[6] -= amount
                  if (type.includes('Coffee')) coffeeVal -= amount
                  else waterVal -= amount
                  updateWaterUI()
               }
             }).catch(err => {
                  waterTotal -= amount
                  waterWeek[6] -= amount
                  if (type.includes('Coffee')) coffeeVal -= amount
                  else waterVal -= amount
                  updateWaterUI()
             })
          }
          
          const logSmoke = (amount, type) => {
             smokeTotal += amount
             smokeWeek[6] += amount
             updateSmokeUI()
             
             self.request({
               method: 'LOG_HABIT',
               params: { access_token: accessToken, user_id: userId, habit_type: 'smokes', value: amount, unit: 'count', metadata: { type: type } }
             }).then(res => {
               if (!res || !res.success) {
                  smokeTotal -= amount
                  smokeWeek[6] -= amount
                  updateSmokeUI()
               }
             }).catch(err => {
                  smokeTotal -= amount
                  smokeWeek[6] -= amount
                  updateSmokeUI()
             })
          }

          const buildDashboard = () => {
             const h = 450 // Screen height
             
             // Snap-to-page scrolling
             try {
                setScrollMode({ mode: SCROLL_MODE_SWIPER, options: { height: h, count: 5 } })
             } catch(e) {
                logger.error('Scroll mode error', e)
             }

             // ================== PAGE 1: BUBBLES ==================
             createWidget(widget.ARC, { x: 10, y: 145, w: 160, h: 160, start_angle: -90, end_angle: 270, color: 0x333333, line_width: 12 })
             waterArc = createWidget(widget.ARC, { x: 10, y: 145, w: 160, h: 160, start_angle: -90, end_angle: -90, color: 0x00ffff, line_width: 12 })
             coffeeArc = createWidget(widget.ARC, { x: 10, y: 145, w: 160, h: 160, start_angle: -90, end_angle: -90, color: 0xffa500, line_width: 12 })
             waterCenterText = createWidget(widget.TEXT, { x: 10, y: 145, w: 160, h: 160, color: 0xffffff, text_size: 20, align_h: align.CENTER_H, align_v: align.CENTER_V, text_style: text_style.WRAP, text: '...' })
             
             createWidget(widget.BUTTON, { x: 190, y: 100, w: 180, h: 70, radius: 35, normal_color: 0x0055ff, press_color: 0x0033aa, text: '+300ml', color: 0xffffff, text_size: 18, click_func: () => logWater(300, 'Large Water') })
             createWidget(widget.BUTTON, { x: 190, y: 190, w: 180, h: 70, radius: 35, normal_color: 0x0055ff, press_color: 0x0033aa, text: '+150ml', color: 0xffffff, text_size: 18, click_func: () => logWater(150, 'Small Water') })
             createWidget(widget.BUTTON, { x: 190, y: 280, w: 180, h: 70, radius: 35, normal_color: 0x8b4513, press_color: 0x5a2d0c, text: '+100ml', color: 0xffffff, text_size: 18, click_func: () => logWater(100, 'Coffee') })

             // ================== PAGE 2: BUBBLES STATS ==================
             createWidget(widget.TEXT, { x: 0, y: h + 100, w: 390, h: 60, color: 0x00aaff, text_size: 24, align_h: align.CENTER_H, align_v: align.CENTER_V, text: 'Hydration 7 Days' })
             
             waterHistogram = createWidget(widget.HISTOGRAM, {
               x: 20, y: h + 170, w: 350, h: 180,
               item_color: 0x00aaff,
               item_bg_color: 0x333333,
               item_width: 30,
               item_space: 15,
               item_radius: 10,
               data_array: waterWeek,
               data_count: 7,
               data_min_value: 0,
               data_max_value: Math.max(waterGoal, ...waterWeek, 1000)
             })

             // ================== PAGE 3: SMOKES ==================
             createWidget(widget.ARC, { x: 10, y: h*2 + 145, w: 160, h: 160, start_angle: -90, end_angle: 270, color: 0x333333, line_width: 12 })
             smokeArc = createWidget(widget.ARC, { x: 10, y: h*2 + 145, w: 160, h: 160, start_angle: -90, end_angle: -90, color: 0x00ff00, line_width: 12 })
             smokeCenterText = createWidget(widget.TEXT, { x: 10, y: h*2 + 145, w: 160, h: 160, color: 0xffffff, text_size: 20, align_h: align.CENTER_H, align_v: align.CENTER_V, text_style: text_style.WRAP, text: '...' })

             createWidget(widget.BUTTON, { x: 190, y: h*2 + 145, w: 180, h: 70, radius: 35, normal_color: 0xff3b30, press_color: 0xaa2010, text: '+1 Cig', color: 0xffffff, text_size: 20, click_func: () => logSmoke(1, 'Cigarette') })
             createWidget(widget.BUTTON, { x: 190, y: h*2 + 235, w: 180, h: 70, radius: 35, normal_color: 0x007aff, press_color: 0x005bb5, text: '+1 Heat', color: 0xffffff, text_size: 20, click_func: () => logSmoke(1, 'Heated Tobacco') })

             // ================== PAGE 4: SMOKES STATS ==================
             createWidget(widget.TEXT, { x: 0, y: h*3 + 100, w: 390, h: 60, color: 0xff5555, text_size: 24, align_h: align.CENTER_H, align_v: align.CENTER_V, text: 'Smoking 7 Days' })
             
             smokeHistogram = createWidget(widget.HISTOGRAM, {
               x: 20, y: h*3 + 170, w: 350, h: 180,
               item_color: 0xff5555,
               item_bg_color: 0x333333,
               item_width: 30,
               item_space: 15,
               item_radius: 10,
               data_array: smokeWeek,
               data_count: 7,
               data_min_value: 0,
               data_max_value: Math.max(smokeBaseline, ...smokeWeek, 10)
             })

             // ================== PAGE 5: ABOUT / SETTINGS ==================
             createWidget(widget.IMG, { x: 145, y: h*4 + 80, src: 'icon.png' })
             createWidget(widget.TEXT, { x: 0, y: h*4 + 200, w: 390, h: 40, color: 0xffffff, text_size: 24, align_h: align.CENTER_H, align_v: align.CENTER_V, text: 'DayOne Orbit' })
             createWidget(widget.TEXT, { x: 0, y: h*4 + 240, w: 390, h: 30, color: 0xaaaaaa, text_size: 16, align_h: align.CENTER_H, align_v: align.CENTER_V, text: 'v1.0.0 Sync App' })
             createWidget(widget.BUTTON, { x: 45, y: h*4 + 320, w: 300, h: 60, radius: 30, normal_color: 0x222222, press_color: 0x111111, text: '⚙️ Unpair & Logout', color: 0xffffff, text_size: 20, click_func: () => { saveFileStr('token.txt', ''); saveFileStr('userid.txt', ''); exit() } })

             
             updateWaterUI()
             updateSmokeUI()
          }
          
          fetchData()

        } else {
          // --- PAIRING UI ---
          const pin = Math.floor(100000 + Math.random() * 900000).toString()

          createWidget(widget.TEXT, { x: 0, y: 80, w: 390, h: 80, color: 0xffffff, text_size: 24, align_h: align.CENTER_H, align_v: align.CENTER_V, text_style: text_style.WRAP, text: 'DayOne Orbit\nPairing PIN' })
          createWidget(widget.TEXT, { x: 0, y: 180, w: 390, h: 100, color: 0x00ff00, text_size: 48, align_h: align.CENTER_H, align_v: align.CENTER_V, text: pin })
          
          const statusText = createWidget(widget.TEXT, { x: 0, y: 280, w: 390, h: 50, color: 0xaaaaaa, text_size: 16, align_h: align.CENTER_H, align_v: align.CENTER_V, text: 'Connecting to phone...' })

          setTimeout(() => {
            statusText.setProperty(prop.TEXT, 'Sending to Phone...')
            
            this.request({ method: 'PAIR_WATCH', params: { pin } })
            .then(response => {
              if (!response || !response.success) {
                statusText.setProperty(prop.TEXT, 'API Error (Phone)')
                statusText.setProperty(prop.COLOR, 0xff0000)
                return
              }

              statusText.setProperty(prop.TEXT, 'Waiting for PC...')
              let attempts = 0;
              const pollTimer = setInterval(() => {
                this.request({ method: 'POLL_WATCH', params: { pin } }).then(pollRes => {
                  try {
                    if (pollRes && pollRes.success && pollRes.data) {
                      const data = pollRes.data;
                      if (data.length > 0 && data[0].claimed === true && data[0].access_token) {
                        clearInterval(pollTimer)
                        statusText.setProperty(prop.TEXT, 'Paired Successfully!')
                        statusText.setProperty(prop.COLOR, 0x00ff00)
                        
                        saveFileStr('token.txt', data[0].access_token)
                        if (data[0].user_id) saveFileStr('userid.txt', data[0].user_id)

                        setTimeout(() => { exit() }, 2000)
                      } else {
                        attempts++
                        if (attempts >= 60) {
                          clearInterval(pollTimer)
                          statusText.setProperty(prop.TEXT, 'Timeout. Restart App.')
                          statusText.setProperty(prop.COLOR, 0xff0000)
                        }
                      }
                    }
                  } catch (e) {}
                })
              }, 3000)
            })
            .catch(err => {
              statusText.setProperty(prop.TEXT, `Phone proxy failed!`)
              statusText.setProperty(prop.COLOR, 0xff0000)
            })
          }, 3000)
        }
      } catch (fatalErr) {
        createWidget(widget.TEXT, { x: 0, y: 0, w: 390, h: 400, color: 0xff0000, text_size: 20, align_h: align.CENTER_H, align_v: align.CENTER_V, text_style: text_style.WRAP, text: fatalErr ? fatalErr.toString() : 'Unknown Error' })
      }
    },
    
    onInit() {},
    onDestroy() {}
  })
)
