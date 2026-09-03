import { createWidget, widget, prop, align, text_style } from '@zos/ui'
import { log } from '@zos/utils'
import { setTimeout, setInterval, clearInterval } from '@zos/timer'
import { BasePage } from '@zeppos/zml/base-page'
import { exit } from '@zos/router'
import { statSync, writeFileSync, readFileSync } from '@zos/fs'
import { setScrollMode, SCROLL_MODE_SWIPER } from '@zos/page'
import { HeartRate, Sleep, Step, BloodOxygen, Calorie } from '@zos/sensor'

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
        
        let accessToken = loadFileStr('token.txt')
        let refreshToken = loadFileStr('refresh_token.txt')
        const userId = loadFileStr('userid.txt')
        const self = this
        
        if (accessToken) {
          // --- LOADING UI ---
          const loadingBg = createWidget(widget.ARC, {
            x: 145, y: 125, w: 100, h: 100,
            start_angle: -90, end_angle: 270,
            color: 0x222222, line_width: 8
          })
          
          const loadingArc = createWidget(widget.ARC, {
            x: 145, y: 125, w: 100, h: 100,
            start_angle: -90, end_angle: 0,
            color: 0x00aaff, line_width: 8
          })
          
          const loadingText = createWidget(widget.TEXT, {
            x: 0, y: 240, w: 390, h: 50,
            color: 0xffffff, text_size: 20,
            align_h: align.CENTER_H, align_v: align.CENTER_V,
            text: 'Orbiting...'
          })
          
          let loadingAngle = -90;
          const loadingTimer = setInterval(() => {
              loadingAngle += 15;
              if (loadingAngle >= 270) loadingAngle = -90;
              loadingArc.setProperty(prop.MORE, { start_angle: loadingAngle, end_angle: loadingAngle + 90 })
          }, 50)

          let waterGoal = 2000
          let smokeBaseline = 20
          
          let waterTotal = 0
          let waterVal = 0
          let coffeeVal = 0
          let waterWeek = [0, 0, 0, 0, 0, 0, 0]
          let coffeeWeek = [0, 0, 0, 0, 0, 0, 0]
          
          let smokeTotal = 0
          let cigVal = 0
          let heatVal = 0
          let smokeWeek = [0, 0, 0, 0, 0, 0, 0]
          let heatWeek = [0, 0, 0, 0, 0, 0, 0]
          
          let waterHistogram;
          let coffeeHistogram;
          let smokeHistogram;
          let heatHistogram;
          
          let debugText;
          let waterBreakdownText;
          let smokeBreakdownText;

          const doRequest = (method, params) => {
             return self.request({ method, params }).then(res => {
                if (res && res.success === false) throw new Error(res.error || 'API Failed')
                return res
             })
          }

          const showError = (msg) => {
             clearInterval(loadingTimer)
             loadingBg.setProperty(prop.VISIBLE, false)
             loadingArc.setProperty(prop.VISIBLE, false)
             loadingText.setProperty(prop.TEXT, msg)
             loadingText.setProperty(prop.COLOR, 0xff0000)
             
             createWidget(widget.BUTTON, {
               x: 45, y: 300, w: 300, h: 60, radius: 30, normal_color: 0x222222, press_color: 0x111111,
               text: '⚙️ Reset App', color: 0xffffff, text_size: 20,
               click_func: () => { saveFileStr('token.txt', ''); saveFileStr('refresh_token.txt', ''); saveFileStr('userid.txt', ''); exit() }
             })
          }

          const fetchData = () => {
             doRequest('GET_PREFS', { access_token: accessToken, user_id: userId })
             .then(res => {
               if (res && res.success && res.data) {
                 waterGoal = res.data.water_goal || 2000
                 smokeBaseline = res.data.smokes_baseline || 20
               }
               
               return doRequest('GET_HABITS_TODAY', { access_token: accessToken, user_id: userId, habit_type: 'water' })
             }).then(res => {
               if (res && res.success && res.data) {
                 waterTotal = res.data.total || 0
                 waterVal = res.data.waterTotal || 0
                 coffeeVal = res.data.coffeeTotal || 0
               }
               
               return doRequest('GET_HABITS_TODAY', { access_token: accessToken, user_id: userId, habit_type: 'smokes' })
             }).then(res => {
               if (res && res.success && res.data) {
                 smokeTotal = res.data.total || 0
                 cigVal = res.data.cigTotal || 0
                 heatVal = res.data.heatTotal || 0
               }
               
               return doRequest('GET_HABITS_WEEK', { access_token: accessToken, habit_type: 'water' })
             }).then(res => {
               if (res && res.success && res.data) {
                 waterWeek = res.data.total || [0,0,0,0,0,0,0]
                 coffeeWeek = res.data.sub || [0,0,0,0,0,0,0]
               }
               
               return doRequest('GET_HABITS_WEEK', { access_token: accessToken, habit_type: 'smokes' })
             }).then(res => {
               if (res && res.success && res.data) {
                 smokeWeek = res.data.total || [0,0,0,0,0,0,0]
                 heatWeek = res.data.sub || [0,0,0,0,0,0,0]
               }
               
               clearInterval(loadingTimer)
               loadingBg.setProperty(prop.VISIBLE, false)
               loadingArc.setProperty(prop.VISIBLE, false)
               loadingText.setProperty(prop.VISIBLE, false)
               buildDashboard()
             }).catch(err => {
               let errMsg = err ? err.toString() : 'Unknown'
               if (err && err.message) errMsg = err.message
               logger.error('Fetch chain error', errMsg)
               
               if (errMsg.includes('401') || errMsg.includes('JWT expired')) {
                  if (!refreshToken) {
                     showError('Session expired. Please Re-Pair.')
                     return
                  }
                  self.request({ method: 'REFRESH_TOKEN', params: { refresh_token: refreshToken } })
                  .then(refRes => {
                     if (refRes && refRes.success && refRes.data) {
                        accessToken = refRes.data.access_token
                        refreshToken = refRes.data.refresh_token
                        saveFileStr('token.txt', accessToken)
                        saveFileStr('refresh_token.txt', refreshToken)
                        fetchData() // Retry!
                     } else {
                        showError('Refresh failed. Please Re-Pair.')
                     }
                  }).catch(e => showError('Network Error. Reset App.'))
                  return
               }
               
               showError('Err: ' + errMsg.substring(0, 50))
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
             
             if (waterBreakdownText) {
                waterBreakdownText.setProperty(prop.TEXT, `Water: ${waterVal} ml | Coffee: ${coffeeVal} ml`)
             }
             
             if (waterHistogram && coffeeHistogram) {
                const maxVal = Math.max(waterGoal, ...waterWeek, 1000)
                waterHistogram.setProperty(prop.UPDATE_DATA, {
                   data_array: waterWeek,
                   data_count: 7,
                   data_min_value: 0,
                   data_max_value: maxVal
                })
                coffeeHistogram.setProperty(prop.UPDATE_DATA, {
                   data_array: coffeeWeek,
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
             
             if (smokeBreakdownText) {
                smokeBreakdownText.setProperty(prop.TEXT, `Cigarettes: ${cigVal} | Heated: ${heatVal}`)
             }
             
             if (smokeHistogram && heatHistogram) {
                const maxVal = Math.max(smokeBaseline, ...smokeWeek, 10)
                smokeHistogram.setProperty(prop.UPDATE_DATA, {
                   data_array: smokeWeek,
                   data_count: 7,
                   data_min_value: 0,
                   data_max_value: maxVal
                })
                heatHistogram.setProperty(prop.UPDATE_DATA, {
                   data_array: heatWeek,
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
             if (type.includes('Coffee')) {
                 coffeeVal += amount
                 coffeeWeek[6] += amount
             } else waterVal += amount
             updateWaterUI()
             
             if (debugText) debugText.setProperty(prop.TEXT, '')
             
             self.request({
               method: 'LOG_HABIT',
               params: { access_token: accessToken, user_id: userId, habit_type: 'water', value: amount, unit: 'ml', metadata: { drink: type } }
             }).then(res => {
               if (!res || !res.success) {
                  if (debugText) debugText.setProperty(prop.TEXT, res?.error || 'Log Failed')
                  waterTotal -= amount
                  waterWeek[6] -= amount
                  if (type.includes('Coffee')) {
                      coffeeVal -= amount
                      coffeeWeek[6] -= amount
                  } else waterVal -= amount
                  updateWaterUI()
               }
             }).catch(err => {
                  if (debugText) debugText.setProperty(prop.TEXT, err ? err.toString() : 'Net Err')
                  waterTotal -= amount
                  waterWeek[6] -= amount
                  if (type.includes('Coffee')) {
                      coffeeVal -= amount
                      coffeeWeek[6] -= amount
                  } else waterVal -= amount
                  updateWaterUI()
             })
          }
          
          const logSmoke = (amount, type) => {
             smokeTotal += amount
             smokeWeek[6] += amount
             if (type.includes('Heat') || type.includes('Vape')) {
                 heatVal += amount
                 heatWeek[6] += amount
             } else cigVal += amount
             updateSmokeUI()
             
             if (debugText) debugText.setProperty(prop.TEXT, '')
             
             self.request({
               method: 'LOG_HABIT',
               params: { access_token: accessToken, user_id: userId, habit_type: 'smokes', value: amount, unit: 'count', metadata: { type: type } }
             }).then(res => {
               if (!res || !res.success) {
                  if (debugText) debugText.setProperty(prop.TEXT, res?.error || 'Log Failed')
                  smokeTotal -= amount
                  smokeWeek[6] -= amount
                  if (type.includes('Heat') || type.includes('Vape')) {
                      heatVal -= amount
                      heatWeek[6] -= amount
                  } else cigVal -= amount
                  updateSmokeUI()
               }
             }).catch(err => {
                  if (debugText) debugText.setProperty(prop.TEXT, err ? err.toString() : 'Net Err')
                  smokeTotal -= amount
                  smokeWeek[6] -= amount
                  if (type.includes('Heat') || type.includes('Vape')) {
                      heatVal -= amount
                      heatWeek[6] -= amount
                  } else cigVal -= amount
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
             
             waterBreakdownText = createWidget(widget.TEXT, { x: 0, y: 315, w: 180, h: 60, color: 0xaaaaaa, text_size: 14, align_h: align.CENTER_H, align_v: align.TOP, text: 'Loading...' })
             
             createWidget(widget.BUTTON, { x: 190, y: 100, w: 180, h: 70, radius: 35, normal_color: 0x0055ff, press_color: 0x0033aa, text: '+300ml', color: 0xffffff, text_size: 18, click_func: () => logWater(300, 'Large Water') })
             createWidget(widget.BUTTON, { x: 190, y: 190, w: 180, h: 70, radius: 35, normal_color: 0x0055ff, press_color: 0x0033aa, text: '+150ml', color: 0xffffff, text_size: 18, click_func: () => logWater(150, 'Small Water') })
             createWidget(widget.BUTTON, { x: 190, y: 280, w: 180, h: 70, radius: 35, normal_color: 0x8b4513, press_color: 0x5a2d0c, text: '+100ml', color: 0xffffff, text_size: 18, click_func: () => logWater(100, 'Coffee') })

             // ================== PAGE 2: BUBBLES STATS ==================
             createWidget(widget.TEXT, { x: 0, y: h + 100, w: 390, h: 60, color: 0x00aaff, text_size: 24, align_h: align.CENTER_H, align_v: align.CENTER_V, text: 'Hydration 7 Days' })
             createWidget(widget.TEXT, { x: 0, y: h + 140, w: 390, h: 30, color: 0xffa500, text_size: 16, align_h: align.CENTER_H, align_v: align.CENTER_V, text: 'Blue: Water | Orange: Coffee' })
             
             waterHistogram = createWidget(widget.HISTOGRAM, {
               x: 20, y: h + 180, w: 350, h: 180,
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
             
             coffeeHistogram = createWidget(widget.HISTOGRAM, {
               x: 20, y: h + 180, w: 350, h: 180,
               item_color: 0xffa500,
               item_bg_color: 0x00000000,
               item_width: 30,
               item_space: 15,
               item_radius: 10,
               data_array: coffeeWeek,
               data_count: 7,
               data_min_value: 0,
               data_max_value: Math.max(waterGoal, ...waterWeek, 1000)
             })

             // ================== PAGE 3: SMOKES ==================
             createWidget(widget.ARC, { x: 10, y: h*2 + 145, w: 160, h: 160, start_angle: -90, end_angle: 270, color: 0x333333, line_width: 12 })
             smokeArc = createWidget(widget.ARC, { x: 10, y: h*2 + 145, w: 160, h: 160, start_angle: -90, end_angle: -90, color: 0x00ff00, line_width: 12 })
             smokeCenterText = createWidget(widget.TEXT, { x: 10, y: h*2 + 145, w: 160, h: 160, color: 0xffffff, text_size: 20, align_h: align.CENTER_H, align_v: align.CENTER_V, text_style: text_style.WRAP, text: '...' })
             
             smokeBreakdownText = createWidget(widget.TEXT, { x: 0, y: h*2 + 315, w: 180, h: 60, color: 0xaaaaaa, text_size: 14, align_h: align.CENTER_H, align_v: align.TOP, text: 'Loading...' })

             createWidget(widget.BUTTON, { x: 190, y: h*2 + 145, w: 180, h: 70, radius: 35, normal_color: 0xff3b30, press_color: 0xaa2010, text: '+1 Cig', color: 0xffffff, text_size: 20, click_func: () => logSmoke(1, 'Cigarette') })
             createWidget(widget.BUTTON, { x: 190, y: h*2 + 235, w: 180, h: 70, radius: 35, normal_color: 0x007aff, press_color: 0x005bb5, text: '+1 Heat', color: 0xffffff, text_size: 20, click_func: () => logSmoke(1, 'Heated Tobacco') })

             // ================== PAGE 4: SMOKES STATS ==================
             createWidget(widget.TEXT, { x: 0, y: h*3 + 100, w: 390, h: 60, color: 0xff5555, text_size: 24, align_h: align.CENTER_H, align_v: align.CENTER_V, text: 'Smoking 7 Days' })
             createWidget(widget.TEXT, { x: 0, y: h*3 + 140, w: 390, h: 30, color: 0x007aff, text_size: 16, align_h: align.CENTER_H, align_v: align.CENTER_V, text: 'Red: Cigs | Blue: Heat' })
             
             smokeHistogram = createWidget(widget.HISTOGRAM, {
               x: 20, y: h*3 + 180, w: 350, h: 180,
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
             
             heatHistogram = createWidget(widget.HISTOGRAM, {
               x: 20, y: h*3 + 180, w: 350, h: 180,
               item_color: 0x007aff,
               item_bg_color: 0x00000000,
               item_width: 30,
               item_space: 15,
               item_radius: 10,
               data_array: heatWeek,
               data_count: 7,
               data_min_value: 0,
               data_max_value: Math.max(smokeBaseline, ...smokeWeek, 10)
             })

             // ================== PAGE 5: ABOUT / SETTINGS ==================
             createWidget(widget.IMG, { x: 145, y: h*4 + 60, src: 'icon.png' })
             createWidget(widget.TEXT, { x: 0, y: h*4 + 180, w: 390, h: 40, color: 0xffffff, text_size: 24, align_h: align.CENTER_H, align_v: align.CENTER_V, text: 'DayOne Orbit' })
             createWidget(widget.TEXT, { x: 0, y: h*4 + 220, w: 390, h: 30, color: 0xaaaaaa, text_size: 16, align_h: align.CENTER_H, align_v: align.CENTER_V, text: 'v1.0.0 Sync App' })
             
             debugText = createWidget(widget.TEXT, { x: 10, y: h*4 + 250, w: 370, h: 80, color: 0xffa500, text_size: 14, align_h: align.CENTER_H, align_v: align.CENTER_V, text_style: text_style.WRAP, text: 'Waiting for health sync...' })
             
             createWidget(widget.BUTTON, { x: 45, y: h*4 + 340, w: 300, h: 60, radius: 30, normal_color: 0x222222, press_color: 0x111111, text: '⚙️ Unpair & Logout', color: 0xffffff, text_size: 20, click_func: () => { saveFileStr('token.txt', ''); saveFileStr('refresh_token.txt', ''); saveFileStr('userid.txt', ''); exit() } })

             
             updateWaterUI()
             updateSmokeUI()
             
             // Poll telemetry every 1 hour (3600000 ms) while app is open, and once on load
             setInterval(syncTelemetry, 3600000)
             setTimeout(syncTelemetry, 1000) // 1 second after dashboard builds
          }
             const syncTelemetry = () => {
             try {
                 const hr = new HeartRate()
                 const sleep = new Sleep()
                 const step = new Step()
                 const bo = new BloodOxygen()
                 
                 // In Zepp OS 3.0, step.getCurrent() and bo.getCurrent() return numbers
                 const hrLast = hr.getLast() || 0
                 const boLast = bo.getCurrent() || bo.getCurrent()?.value || 0
                 
                 let stepCount = 0
                 let calCount = 0
                 try { stepCount = step.getCurrent() || 0 } catch(e) {}
                 try { const cal = new Calorie(); calCount = cal.getCurrent() || 0 } catch(e) {}
                 
                 const payload = []
                 
                 if (hrLast > 0) {
                     payload.push({ type: 'heart_rate', value: hrLast, unit: 'bpm' })
                 }
                 
                 // Fallback if step returns object
                 if (typeof stepCount === 'object') {
                     calCount = stepCount.calorie || calCount
                     stepCount = stepCount.step || 0
                 }
                 
                 if (stepCount > 0) {
                     payload.push({ type: 'steps', value: stepCount, unit: 'count' })
                 }
                 
                 if (calCount > 0) {
                     payload.push({ type: 'active_energy', value: calCount, unit: 'kcal' })
                 }
                 
                 if (boLast > 0) {
                     payload.push({ type: 'blood_oxygen', value: boLast, unit: '%' })
                 }
                 
                 // Granular sleep data using stages
                 const sleepInfo = sleep.getInfo() || {}
                 if (sleepInfo.totalTime > 0) {
                     payload.push({ type: 'sleep_deep', value: sleepInfo.deepTime || 0, unit: 'minutes' })
                     
                     // Aggregate stages manually if getStage is available
                     if (typeof sleep.getStage === 'function') {
                         let light = 0, rem = 0, awake = 0
                         const stages = sleep.getStage() || []
                         const constants = sleep.getStageConstantObj ? sleep.getStageConstantObj() : { LIGHT_STAGE: 1, DEEP_STAGE: 2, REM_STAGE: 3, WAKE_STAGE: 0 }
                         
                         stages.forEach(st => {
                             const dur = st.stop - st.start
                             if (dur > 0) {
                                 if (st.model === constants.LIGHT_STAGE) light += dur
                                 else if (st.model === constants.REM_STAGE) rem += dur
                                 else if (st.model === constants.WAKE_STAGE) awake += dur
                             }
                         })
                         
                         if (light > 0) payload.push({ type: 'sleep_light', value: light, unit: 'minutes' })
                         if (rem > 0) payload.push({ type: 'sleep_rem', value: rem, unit: 'minutes' })
                         if (awake > 0) payload.push({ type: 'sleep_awake', value: awake, unit: 'minutes' })
                     } else {
                         // Fallback math
                         const light = sleepInfo.totalTime - (sleepInfo.deepTime || 0)
                         if (light > 0) payload.push({ type: 'sleep_light', value: light, unit: 'minutes' })
                     }
                 }
                 
                 if (payload.length > 0) {
                    if (debugText) debugText.setProperty(prop.TEXT, `Sending ${payload.length} sensors...`)
                    self.request({
                        method: 'SYNC_TELEMETRY',
                        params: { access_token: accessToken, user_id: userId, telemetry: payload }
                    }).then(res => {
                        const d = new Date()
                        const timeStr = d.getHours() + ':' + (d.getMinutes()<10?'0':'') + d.getMinutes()
                        if (debugText) debugText.setProperty(prop.TEXT, res?.success ? `Health data successfully synced at ${timeStr}` : `Sync Failed: ${res?.error || 'Unknown'}`)
                    }).catch(e => {
                        logger.error('Telemetry push failed', e)
                        if (debugText) debugText.setProperty(prop.TEXT, `Sync err: ${e}`)
                    })
                } else {
                    if (debugText) debugText.setProperty(prop.TEXT, 'No sensor data')
                }
             } catch(err) {
                 logger.error('Sensor read failed', err)
                 if (debugText) debugText.setProperty(prop.TEXT, `Read err: ${err}`)
             }
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
                        if (data[0].refresh_token) saveFileStr('refresh_token.txt', data[0].refresh_token)
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
