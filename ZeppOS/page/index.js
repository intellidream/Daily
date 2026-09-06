import { createWidget, widget, prop, align, text_style } from '@zos/ui'
import { log } from '@zos/utils'
import { setTimeout, setInterval, clearInterval } from '@zos/timer'
import { BasePage } from '@zeppos/zml/base-page'
import { exit } from '@zos/router'
import { statSync, writeFileSync, readFileSync } from '@zos/fs'
import { setScrollMode, SCROLL_MODE_SWIPER } from '@zos/page'
import { HeartRate, Sleep, Step, BloodOxygen, Calorie, Stress, Pai } from '@zos/sensor'
import { getDeviceInfo, SCREEN_SHAPE_ROUND } from '@zos/device'

const logger = log.getLogger('dayone-orbit')

const SQUARE_CONFIG = {
  screenW: 390,
  screenH: 450,
  pageH: 450,
  syncIndicator: { iconX: 141, iconY: 406, iconW: 20, iconH: 20, textX: 169, textY: 404, textW: 100, textH: 24, text_size: 15 },
  loading: {
    arc: { x: 145, y: 125, w: 100, h: 100, line_width: 8 },
    text: { x: 0, y: 240, w: 390, h: 50, text_size: 20 },
    btn: { x: 45, y: 300, w: 300, h: 60, radius: 30, text_size: 20 }
  },
  pageTitleY: 80,
  pageTitleSize: 24,
  arc: { x: 20, y: 150, w: 200, h: 200, line_width: 16, text_size: 26 },
  breakdownText: { x: 0, y: 358, w: 390, h: 26, text_size: 14, align_h: align.CENTER_H, align_v: align.CENTER_V },
  p1Buttons: {
    x: 240,
    w: 130,
    h: 58,
    radius: 29,
    text_size: 22,
    y1: 145,
    y2: 217,
    y3: 289
  },
  p3Buttons: {
    x: 240,
    w: 130,
    h: 62,
    radius: 31,
    text_size: 22,
    y1: 180,
    y2: 258
  },
  chart: {
    titleY: 80,
    titleSize: 24,
    x: 20,
    y: 145,
    w: 350,
    h: 195,
    item_width: 30,
    item_space: 15,
    item_radius: 10,
    legendY: 358,
    legendSize: 15
  },
  about: {
    iconSrc: 'icon.png',
    iconX: 133,
    iconY: 40,
    nameY: 180,
    nameSize: 24,
    verY: 220,
    verSize: 16,
    debug: { x: 10, y: 250, w: 370, h: 80, text_size: 14 },
    unpairBtn: { x: 45, y: 340, w: 300, h: 60, radius: 30, text_size: 20 }
  },
  pairing: {
    title: { x: 0, y: 80, w: 390, h: 80, text_size: 24 },
    pin: { x: 0, y: 180, w: 390, h: 100, text_size: 48 },
    status: { x: 0, y: 280, w: 390, h: 50, text_size: 16 }
  }
}

const ROUND_CONFIG = {
  screenW: 480,
  screenH: 480,
  pageH: 480,
  syncIndicator: { iconX: 186, iconY: 418, iconW: 20, iconH: 20, textX: 214, textY: 416, textW: 100, textH: 24, text_size: 15 },
  loading: {
    arc: { x: 180, y: 140, w: 120, h: 120, line_width: 10 },
    text: { x: 0, y: 280, w: 480, h: 50, text_size: 22 },
    btn: { x: 80, y: 320, w: 320, h: 64, radius: 32, text_size: 22 }
  },
  pageTitleY: 50,
  pageTitleSize: 26,
  arc: { x: 30, y: 136, w: 216, h: 216, line_width: 18, text_size: 28 },
  breakdownText: { x: 30, y: 366, w: 420, h: 26, text_size: 14, align_h: align.CENTER_H, align_v: align.CENTER_V },
  p1Buttons: {
    x: 265,
    w: 165,
    h: 62,
    radius: 31,
    text_size: 22,
    y1: 136,
    y2: 210,
    y3: 284
  },
  p3Buttons: {
    x: 265,
    w: 165,
    h: 68,
    radius: 34,
    text_size: 24,
    y1: 168,
    y2: 252
  },
  chart: {
    titleY: 50,
    titleSize: 26,
    x: 70,
    y: 135,
    w: 340,
    h: 215,
    item_width: 28,
    item_space: 14,
    item_radius: 10,
    legendY: 366,
    legendSize: 15
  },
  about: {
    iconSrc: 'logo.png',
    iconX: 185,
    iconY: 35,
    nameY: 165,
    nameSize: 26,
    verY: 202,
    verSize: 16,
    debug: { x: 40, y: 235, w: 400, h: 75, text_size: 14 },
    unpairBtn: { x: 70, y: 325, w: 340, h: 60, radius: 30, text_size: 20 }
  },
  pairing: {
    title: { x: 0, y: 80, w: 480, h: 80, text_size: 26 },
    pin: { x: 0, y: 175, w: 480, h: 100, text_size: 54 },
    status: { x: 0, y: 295, w: 480, h: 50, text_size: 18 }
  }
}

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
      let isRound = false
      let screenW = 390
      let screenH = 450
      try {
        const devInfo = getDeviceInfo()
        if (devInfo) {
          screenW = devInfo.width || 390
          screenH = devInfo.height || 450
          isRound = devInfo.screenShape === SCREEN_SHAPE_ROUND || screenW === 480 || (devInfo.width === devInfo.height && devInfo.width >= 454)
        }
      } catch (e) {
        logger.error('getDeviceInfo error', e)
      }
      const cfg = isRound ? ROUND_CONFIG : SQUARE_CONFIG

      try {
        logger.info('page build invoked')
        
        let accessToken = loadFileStr('token.txt')
        let refreshToken = loadFileStr('refresh_token.txt')
        const userId = loadFileStr('userid.txt')
        const self = this
        
        if (accessToken) {
          let waterGoal = 2000
          let smokeBaseline = 20
          let waterTotal = 0, waterVal = 0, coffeeVal = 0
          let waterWeek = [0, 0, 0, 0, 0, 0, 0]
          let coffeeWeek = [0, 0, 0, 0, 0, 0, 0]
          
          let smokeTotal = 0, cigVal = 0, heatVal = 0
          let smokeWeek = [0, 0, 0, 0, 0, 0, 0]
          let heatWeek = [0, 0, 0, 0, 0, 0, 0]
          
          let waterHistogram, coffeeHistogram, smokeHistogram, heatHistogram
          let debugText, waterBreakdownText, smokeBreakdownText
          let syncIcon, syncText
          let isSyncingState = false
          let isDashboardBuilt = false

          const setSyncing = (isSyncing) => {
             isSyncingState = isSyncing
             if (syncIcon) syncIcon.setProperty(prop.VISIBLE, isSyncing)
             if (syncText) syncText.setProperty(prop.VISIBLE, isSyncing)
          }

          const saveCache = () => {
             try {
               const cache = { waterGoal, smokeBaseline, waterTotal, waterVal, coffeeVal, waterWeek, coffeeWeek, smokeTotal, cigVal, heatVal, smokeWeek, heatWeek }
               saveFileStr('habits_cache.json', JSON.stringify(cache))
             } catch(e) {}
          }

          let hasCache = false
          try {
             const cStr = loadFileStr('habits_cache.json')
             if (cStr) {
                const c = JSON.parse(cStr)
                waterGoal = c.waterGoal || 2000; smokeBaseline = c.smokeBaseline || 20;
                waterTotal = c.waterTotal || 0; waterVal = c.waterVal || 0; coffeeVal = c.coffeeVal || 0;
                waterWeek = c.waterWeek || [0,0,0,0,0,0,0]; coffeeWeek = c.coffeeWeek || [0,0,0,0,0,0,0];
                smokeTotal = c.smokeTotal || 0; cigVal = c.cigVal || 0; heatVal = c.heatVal || 0;
                smokeWeek = c.smokeWeek || [0,0,0,0,0,0,0]; heatWeek = c.heatWeek || [0,0,0,0,0,0,0];
                hasCache = true
             }
          } catch(e) {}

          let loadingBg, loadingArc, loadingText, loadingTimer
          
          if (!hasCache) {
              loadingBg = createWidget(widget.ARC, { x: cfg.loading.arc.x, y: cfg.loading.arc.y, w: cfg.loading.arc.w, h: cfg.loading.arc.h, start_angle: -90, end_angle: 270, color: 0x222222, line_width: cfg.loading.arc.line_width })
              loadingArc = createWidget(widget.ARC, { x: cfg.loading.arc.x, y: cfg.loading.arc.y, w: cfg.loading.arc.w, h: cfg.loading.arc.h, start_angle: -90, end_angle: 0, color: 0x00aaff, line_width: cfg.loading.arc.line_width })
              loadingText = createWidget(widget.TEXT, { x: cfg.loading.text.x, y: cfg.loading.text.y, w: cfg.loading.text.w, h: cfg.loading.text.h, color: 0xffffff, text_size: cfg.loading.text.text_size, align_h: align.CENTER_H, align_v: align.CENTER_V, text: 'Orbiting...' })
              
              let loadingAngle = -90;
              loadingTimer = setInterval(() => {
                  loadingAngle += 15;
                  if (loadingAngle >= 270) loadingAngle = -90;
                  loadingArc.setProperty(prop.MORE, { start_angle: loadingAngle, end_angle: loadingAngle + 90 })
              }, 50)
          }

          const doRequest = (method, params) => {
             return self.request({ method, params }).then(res => {
                if (res && res.success === false) throw new Error(res.error || 'API Failed')
                return res
             })
          }

          const showError = (msg) => {
             if (loadingTimer) clearInterval(loadingTimer)
             if (loadingBg) loadingBg.setProperty(prop.VISIBLE, false)
             if (loadingArc) loadingArc.setProperty(prop.VISIBLE, false)
             if (loadingText) {
                 loadingText.setProperty(prop.TEXT, msg)
                 loadingText.setProperty(prop.COLOR, 0xff0000)
             }
             
             createWidget(widget.BUTTON, {
               x: cfg.loading.btn.x, y: cfg.loading.btn.y, w: cfg.loading.btn.w, h: cfg.loading.btn.h, radius: cfg.loading.btn.radius, normal_color: 0x222222, press_color: 0x111111,
               text: '⚙️ Reset App', color: 0xffffff, text_size: cfg.loading.btn.text_size,
               click_func: () => { saveFileStr('token.txt', ''); saveFileStr('refresh_token.txt', ''); saveFileStr('userid.txt', ''); exit() }
             })
          }

          const fetchData = () => {
             setSyncing(true)
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
               
               saveCache()
               
               if (loadingTimer) clearInterval(loadingTimer)
               if (loadingBg) loadingBg.setProperty(prop.VISIBLE, false)
               if (loadingArc) loadingArc.setProperty(prop.VISIBLE, false)
               if (loadingText) loadingText.setProperty(prop.VISIBLE, false)
               
               setSyncing(false)
               
               if (!isDashboardBuilt) {
                   buildDashboard()
               } else {
                   updateWaterUI()
                   updateSmokeUI()
               }
             }).catch(err => {
               setSyncing(false)
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
                  if (debugText) debugText.setProperty(prop.TEXT, (res && res.error) ? res.error : 'Log Failed')
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
                  if (debugText) debugText.setProperty(prop.TEXT, (res && res.error) ? res.error : 'Log Failed')
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
             const h = cfg.pageH
             
             // Snap-to-page scrolling
             try {
                setScrollMode({ mode: SCROLL_MODE_SWIPER, options: { height: h, count: 5 } })
             } catch(e) {
                logger.error('Scroll mode error', e)
             }

             // ================== PAGE 1: BUBBLES ==================
             syncIcon = createWidget(widget.IMG, {
                x: cfg.syncIndicator.iconX, y: cfg.syncIndicator.iconY,
                src: 'sync.png'
             })
             syncIcon.setProperty(prop.VISIBLE, isSyncingState)

             syncText = createWidget(widget.TEXT, {
                x: cfg.syncIndicator.textX, y: cfg.syncIndicator.textY, w: cfg.syncIndicator.textW, h: cfg.syncIndicator.textH,
                color: 0x00ff00, text_size: cfg.syncIndicator.text_size, align_h: align.LEFT, align_v: align.CENTER_V, text: 'Syncing...'
             })
             syncText.setProperty(prop.VISIBLE, isSyncingState)
             
             createWidget(widget.TEXT, {
                x: 0, y: cfg.pageTitleY, w: cfg.screenW, h: 40,
                color: 0x00aaff, text_size: cfg.pageTitleSize, align_h: align.CENTER_H, align_v: align.CENTER_V, text: '💧 Bubbles'
             })
             
             createWidget(widget.ARC, {
                x: cfg.arc.x, y: cfg.arc.y, w: cfg.arc.w, h: cfg.arc.h,
                start_angle: -90, end_angle: 270, color: 0x333333, line_width: cfg.arc.line_width
             })
             waterArc = createWidget(widget.ARC, {
                x: cfg.arc.x, y: cfg.arc.y, w: cfg.arc.w, h: cfg.arc.h,
                start_angle: -90, end_angle: -90, color: 0x00ffff, line_width: cfg.arc.line_width
             })
             coffeeArc = createWidget(widget.ARC, {
                x: cfg.arc.x, y: cfg.arc.y, w: cfg.arc.w, h: cfg.arc.h,
                start_angle: -90, end_angle: -90, color: 0xffa500, line_width: cfg.arc.line_width
             })
             waterCenterText = createWidget(widget.TEXT, {
                x: cfg.arc.x, y: cfg.arc.y, w: cfg.arc.w, h: cfg.arc.h,
                color: 0xffffff, text_size: cfg.arc.text_size, align_h: align.CENTER_H, align_v: align.CENTER_V, text_style: text_style.WRAP, text: '...'
             })
             
             waterBreakdownText = createWidget(widget.TEXT, {
                x: cfg.breakdownText.x, y: cfg.breakdownText.y, w: cfg.breakdownText.w, h: cfg.breakdownText.h,
                color: 0xaaaaaa, text_size: cfg.breakdownText.text_size, align_h: cfg.breakdownText.align_h, align_v: cfg.breakdownText.align_v, text: 'Loading...'
             })
             
             createWidget(widget.BUTTON, {
                x: cfg.p1Buttons.x, y: cfg.p1Buttons.y1, w: cfg.p1Buttons.w, h: cfg.p1Buttons.h, radius: cfg.p1Buttons.radius,
                normal_color: 0x222222, press_color: 0x111111, text: '💧 300', color: 0xffffff, text_size: cfg.p1Buttons.text_size,
                click_func: () => logWater(300, 'Large Water')
             })
             createWidget(widget.BUTTON, {
                x: cfg.p1Buttons.x, y: cfg.p1Buttons.y2, w: cfg.p1Buttons.w, h: cfg.p1Buttons.h, radius: cfg.p1Buttons.radius,
                normal_color: 0x222222, press_color: 0x111111, text: '💧 150', color: 0xffffff, text_size: cfg.p1Buttons.text_size,
                click_func: () => logWater(150, 'Small Water')
             })
             createWidget(widget.BUTTON, {
                x: cfg.p1Buttons.x, y: cfg.p1Buttons.y3, w: cfg.p1Buttons.w, h: cfg.p1Buttons.h, radius: cfg.p1Buttons.radius,
                normal_color: 0x222222, press_color: 0x111111, text: '☕ 100', color: 0xffffff, text_size: cfg.p1Buttons.text_size,
                click_func: () => logWater(100, 'Coffee')
             })

             // ================== PAGE 2: BUBBLES STATS ==================
             createWidget(widget.TEXT, {
                x: 0, y: h + cfg.chart.titleY, w: cfg.screenW, h: 40,
                color: 0x00aaff, text_size: cfg.chart.titleSize, align_h: align.CENTER_H, align_v: align.CENTER_V, text: '💧 Bubbles 7 Days'
             })
             
             waterHistogram = createWidget(widget.HISTOGRAM, {
               x: cfg.chart.x, y: h + cfg.chart.y, w: cfg.chart.w, h: cfg.chart.h,
               item_color: 0x00aaff,
               item_bg_color: 0x333333,
               item_width: cfg.chart.item_width,
               item_space: cfg.chart.item_space,
               item_radius: cfg.chart.item_radius,
               data_array: waterWeek,
               data_count: 7,
               data_min_value: 0,
               data_max_value: Math.max(waterGoal, ...waterWeek, 1000)
             })
             
             coffeeHistogram = createWidget(widget.HISTOGRAM, {
               x: cfg.chart.x, y: h + cfg.chart.y, w: cfg.chart.w, h: cfg.chart.h,
               item_color: 0xffa500,
               item_bg_color: 0x00000000,
               item_width: cfg.chart.item_width,
               item_space: cfg.chart.item_space,
               item_radius: cfg.chart.item_radius,
               data_array: coffeeWeek,
               data_count: 7,
               data_min_value: 0,
               data_max_value: Math.max(waterGoal, ...waterWeek, 1000)
             })

             createWidget(widget.TEXT, {
                x: 0, y: h + cfg.chart.legendY, w: cfg.screenW, h: 30,
                color: 0xffa500, text_size: cfg.chart.legendSize, align_h: align.CENTER_H, align_v: align.CENTER_V, text: 'Blue: Water | Orange: Coffee'
             })

             // ================== PAGE 3: SMOKES ==================
             createWidget(widget.TEXT, {
                x: 0, y: h*2 + cfg.pageTitleY, w: cfg.screenW, h: 40,
                color: 0xff5555, text_size: cfg.pageTitleSize, align_h: align.CENTER_H, align_v: align.CENTER_V, text: '🔥 Smokes'
             })
             
             createWidget(widget.ARC, {
                x: cfg.arc.x, y: h*2 + cfg.arc.y, w: cfg.arc.w, h: cfg.arc.h,
                start_angle: -90, end_angle: 270, color: 0x333333, line_width: cfg.arc.line_width
             })
             smokeArc = createWidget(widget.ARC, {
                x: cfg.arc.x, y: h*2 + cfg.arc.y, w: cfg.arc.w, h: cfg.arc.h,
                start_angle: -90, end_angle: -90, color: 0x00ff00, line_width: cfg.arc.line_width
             })
             smokeCenterText = createWidget(widget.TEXT, {
                x: cfg.arc.x, y: h*2 + cfg.arc.y, w: cfg.arc.w, h: cfg.arc.h,
                color: 0xffffff, text_size: cfg.arc.text_size, align_h: align.CENTER_H, align_v: align.CENTER_V, text_style: text_style.WRAP, text: '...'
             })
             
             smokeBreakdownText = createWidget(widget.TEXT, {
                x: cfg.breakdownText.x, y: h*2 + cfg.breakdownText.y, w: cfg.breakdownText.w, h: cfg.breakdownText.h,
                color: 0xaaaaaa, text_size: cfg.breakdownText.text_size, align_h: cfg.breakdownText.align_h, align_v: cfg.breakdownText.align_v, text: 'Loading...'
             })

             createWidget(widget.BUTTON, {
                x: cfg.p3Buttons.x, y: h*2 + cfg.p3Buttons.y1, w: cfg.p3Buttons.w, h: cfg.p3Buttons.h, radius: cfg.p3Buttons.radius,
                normal_color: 0x222222, press_color: 0x111111, text: '🔥 Cig', color: 0xffffff, text_size: cfg.p3Buttons.text_size,
                click_func: () => logSmoke(1, 'Cigarette')
             })
             createWidget(widget.BUTTON, {
                x: cfg.p3Buttons.x, y: h*2 + cfg.p3Buttons.y2, w: cfg.p3Buttons.w, h: cfg.p3Buttons.h, radius: cfg.p3Buttons.radius,
                normal_color: 0x222222, press_color: 0x111111, text: '⚡ Heat', color: 0xffffff, text_size: cfg.p3Buttons.text_size,
                click_func: () => logSmoke(1, 'Heated Tobacco')
             })

             // ================== PAGE 4: SMOKES STATS ==================
             createWidget(widget.TEXT, {
                x: 0, y: h*3 + cfg.chart.titleY, w: cfg.screenW, h: 40,
                color: 0xff5555, text_size: cfg.chart.titleSize, align_h: align.CENTER_H, align_v: align.CENTER_V, text: '🔥 Smokes 7 Days'
             })
             
             smokeHistogram = createWidget(widget.HISTOGRAM, {
               x: cfg.chart.x, y: h*3 + cfg.chart.y, w: cfg.chart.w, h: cfg.chart.h,
               item_color: 0xff3b30,
               item_bg_color: 0x333333,
               item_width: cfg.chart.item_width,
               item_space: cfg.chart.item_space,
               item_radius: cfg.chart.item_radius,
               data_array: smokeWeek,
               data_count: 7,
               data_min_value: 0,
               data_max_value: Math.max(smokeBaseline, ...smokeWeek, 10)
             })
             
             heatHistogram = createWidget(widget.HISTOGRAM, {
               x: cfg.chart.x, y: h*3 + cfg.chart.y, w: cfg.chart.w, h: cfg.chart.h,
               item_color: 0x007aff,
               item_bg_color: 0x00000000,
               item_width: cfg.chart.item_width,
               item_space: cfg.chart.item_space,
               item_radius: cfg.chart.item_radius,
               data_array: heatWeek,
               data_count: 7,
               data_min_value: 0,
               data_max_value: Math.max(smokeBaseline, ...smokeWeek, 10)
             })

             createWidget(widget.TEXT, {
                x: 0, y: h*3 + cfg.chart.legendY, w: cfg.screenW, h: 30,
                color: 0x007aff, text_size: cfg.chart.legendSize, align_h: align.CENTER_H, align_v: align.CENTER_V, text: 'Red: Cigs | Blue: Heat'
             })

             // ================== PAGE 5: ABOUT / SETTINGS ==================
             createWidget(widget.IMG, { x: cfg.about.iconX, y: h*4 + cfg.about.iconY, src: cfg.about.iconSrc })
             createWidget(widget.TEXT, {
                x: 0, y: h*4 + cfg.about.nameY, w: cfg.screenW, h: 40,
                color: 0xffffff, text_size: cfg.about.nameSize, align_h: align.CENTER_H, align_v: align.CENTER_V, text: 'DayOne Orbit'
             })
             createWidget(widget.TEXT, {
                x: 0, y: h*4 + cfg.about.verY, w: cfg.screenW, h: 30,
                color: 0xaaaaaa, text_size: cfg.about.verSize, align_h: align.CENTER_H, align_v: align.CENTER_V, text: 'v1.0'
             })
             
             debugText = createWidget(widget.TEXT, {
                x: cfg.about.debug.x, y: h*4 + cfg.about.debug.y, w: cfg.about.debug.w, h: cfg.about.debug.h,
                color: 0xffa500, text_size: cfg.about.debug.text_size, align_h: align.CENTER_H, align_v: align.CENTER_V, text_style: text_style.WRAP, text: 'Waiting for health sync...'
             })
             
             createWidget(widget.BUTTON, {
                x: cfg.about.unpairBtn.x, y: h*4 + cfg.about.unpairBtn.y, w: cfg.about.unpairBtn.w, h: cfg.about.unpairBtn.h, radius: cfg.about.unpairBtn.radius,
                normal_color: 0x222222, press_color: 0x111111, text: '⚙️ Unpair & Logout', color: 0xffffff, text_size: cfg.about.unpairBtn.text_size,
                click_func: () => { saveFileStr('token.txt', ''); saveFileStr('refresh_token.txt', ''); saveFileStr('userid.txt', ''); exit() }
             })

             
             updateWaterUI()
             updateSmokeUI()
             
             // Force UI redraw loop to workaround Zepp OS stale texture bug on Swiper pages
             setInterval(() => {
                 updateWaterUI()
                 updateSmokeUI()
             }, 2000)
             
             // Poll telemetry every 1 hour (3600000 ms) while app is open, and once on load
             setInterval(syncTelemetry, 3600000)
             setTimeout(syncTelemetry, 1000) // 1 second after dashboard builds
          }
          const syncTelemetry = () => {
             setSyncing(true)
             try {
                 const hr = new HeartRate()
                 const sleep = new Sleep()
                 const step = new Step()
                 const bo = new BloodOxygen()
                 
                 // In Zepp OS 3.0, step.getCurrent() and bo.getCurrent() return numbers
                 const hrLast = hr.getLast() || 0
                 const boLast = bo.getCurrent() || (bo.getCurrent() && bo.getCurrent().value) || 0
                 
                 let stepCount = 0
                 let calCount = 0
                 try { stepCount = step.getCurrent() || 0 } catch(e) {}
                 try { const cal = new Calorie(); calCount = cal.getCurrent() || 0 } catch(e) {}

                 let tCache = {}
                 try {
                     const tStr = loadFileStr('telemetry_cache.json')
                     if (tStr) tCache = JSON.parse(tStr)
                 } catch(e) {}
                 
                 const todayStr = new Date().toISOString().split('T')[0]
                 if (tCache.date !== todayStr) {
                     tCache = { date: todayStr, steps: 0, active_energy: 0, heart_rate: 0, blood_oxygen: 0, stress: 0, pai: 0, sleep_keys: [] }
                 }
                 if (!tCache.sleep_keys) tCache.sleep_keys = []
                 
                 const payload = []
                 
                 if (hrLast > 0 && hrLast !== tCache.heart_rate) {
                     payload.push({ type: 'heart_rate', value: hrLast, unit: 'bpm' })
                 }
                 
                 // Fallback if step returns object
                 if (typeof stepCount === 'object') {
                     calCount = stepCount.calorie || calCount
                     stepCount = stepCount.step || 0
                 }
                 
                 if (stepCount > 0 && stepCount > (tCache.steps || 0)) {
                     payload.push({ type: 'steps', value: stepCount, unit: 'count' })
                 }
                 
                 if (calCount > 0 && calCount > (tCache.active_energy || 0)) {
                     payload.push({ type: 'active_energy', value: calCount, unit: 'kcal' })
                 }
                 
                 if (boLast > 0 && boLast !== tCache.blood_oxygen) {
                     payload.push({ type: 'blood_oxygen', value: boLast, unit: '%' })
                 }
                 
                 // Stress and PAI
                 let stressVal = 0; let paiVal = 0;
                 try { const str = new Stress(); const s = str.getCurrent(); stressVal = (s && s.value) ? s.value : (s || 0) } catch(e) {}
                 try { const p = new Pai(); paiVal = p.getToday() || 0 } catch(e) {}
                 
                 if (stressVal > 0 && stressVal !== tCache.stress) payload.push({ type: 'stress', value: stressVal, unit: 'score' })
                 if (paiVal > 0 && paiVal !== tCache.pai) payload.push({ type: 'pai', value: paiVal, unit: 'score' })
                 
                 const nowD = new Date()
                 const midnightAnchor = new Date(nowD.getFullYear(), nowD.getMonth(), nowD.getDate(), 0, 0, 0, 0).getTime()

                 // Granular sleep data using precise stages graph
                 const sleepInfo = sleep.getInfo() || {}
                 if (sleepInfo.totalTime > 0) {
                     if (typeof sleep.getStage === 'function') {
                         const stages = sleep.getStage() || []
                         const constants = sleep.getStageConstantObj ? sleep.getStageConstantObj() : { LIGHT_STAGE: 1, DEEP_STAGE: 2, REM_STAGE: 3, WAKE_STAGE: 0 }
                         
                         stages.forEach(st => {
                             const dur = st.stop - st.start
                             if (dur > 0) {
                                 let sType = 'sleep_stage_unknown'
                                 if (st.model === constants.LIGHT_STAGE) sType = 'sleep_stage_light'
                                 else if (st.model === constants.DEEP_STAGE) sType = 'sleep_stage_deep'
                                 else if (st.model === constants.REM_STAGE) sType = 'sleep_stage_rem'
                                 else if (st.model === constants.WAKE_STAGE) sType = 'sleep_stage_awake'
                                 
                                 const startIso = new Date(midnightAnchor + st.start * 60000).toISOString()
                                 const endIso = new Date(midnightAnchor + st.stop * 60000).toISOString()
                                 const key = `${startIso}-${endIso}-${sType}`
                                 if (!tCache.sleep_keys.includes(key)) {
                                     payload.push({ type: sType, value: dur, unit: 'minutes', start_time: startIso, end_time: endIso })
                                 }
                             }
                         })
                     } else {
                         payload.push({ type: 'sleep_deep', value: sleepInfo.deepTime || 0, unit: 'minutes' })
                         const light = sleepInfo.totalTime - (sleepInfo.deepTime || 0)
                         if (light > 0) payload.push({ type: 'sleep_light', value: light, unit: 'minutes' })
                     }
                 }
                 
                 // Naps
                 if (typeof sleep.getNap === 'function') {
                     const naps = sleep.getNap() || []
                     naps.forEach(nap => {
                         const dur = nap.stop - nap.start
                         if (dur > 0) {
                             const startIso = new Date(midnightAnchor + nap.start * 60000).toISOString()
                             const endIso = new Date(midnightAnchor + nap.stop * 60000).toISOString()
                             const key = `${startIso}-${endIso}-sleep_nap`
                             if (!tCache.sleep_keys.includes(key)) {
                                 payload.push({ type: 'sleep_nap', value: dur, unit: 'minutes', start_time: startIso, end_time: endIso })
                             }
                         }
                     })
                 }
                 
                 if (payload.length > 0) {
                    if (debugText) debugText.setProperty(prop.TEXT, `Sending ${payload.length} sensors...`)
                    self.request({
                        method: 'SYNC_TELEMETRY',
                        params: { access_token: accessToken, user_id: userId, telemetry: payload }
                    }).then(res => {
                        const d = new Date()
                        const timeStr = d.getHours() + ':' + (d.getMinutes()<10?'0':'') + d.getMinutes()
                        if (res && res.success) {
                            if (hrLast > 0) tCache.heart_rate = hrLast
                            if (stepCount > 0) tCache.steps = stepCount
                            if (calCount > 0) tCache.active_energy = calCount
                            if (boLast > 0) tCache.blood_oxygen = boLast
                            if (stressVal > 0) tCache.stress = stressVal
                            if (paiVal > 0) tCache.pai = paiVal
                            payload.forEach(p => {
                               if (p.type.startsWith('sleep_')) tCache.sleep_keys.push(`${p.start_time}-${p.end_time}-${p.type}`)
                            })
                            if (tCache.sleep_keys.length > 100) tCache.sleep_keys = tCache.sleep_keys.slice(-100)
                            try { saveFileStr('telemetry_cache.json', JSON.stringify(tCache)) } catch(e) {}
                            
                            if (debugText) debugText.setProperty(prop.TEXT, `Health data successfully synced at ${timeStr}`)
                        } else {
                            if (debugText) debugText.setProperty(prop.TEXT, `Sync Failed: ${(res && res.error) ? res.error : 'Unknown'}`)
                        }
                        setSyncing(false)
                    }).catch(e => {
                        logger.error('Telemetry push failed', e)
                        if (debugText) debugText.setProperty(prop.TEXT, `Sync err: ${e}`)
                        setSyncing(false)
                    })
                } else {
                    if (debugText) debugText.setProperty(prop.TEXT, 'No new sensor data')
                    setSyncing(false)
                }
             } catch(err) {
                 logger.error('Sensor read failed', err)
                 if (debugText) debugText.setProperty(prop.TEXT, `Read err: ${err}`)
                 setSyncing(false)
             }
          }
          if (hasCache) {
             buildDashboard()
             isDashboardBuilt = true
          }
          fetchData()

        } else {
          // --- PAIRING UI ---
          const pin = Math.floor(100000 + Math.random() * 900000).toString()

          createWidget(widget.TEXT, {
            x: cfg.pairing.title.x, y: cfg.pairing.title.y, w: cfg.pairing.title.w, h: cfg.pairing.title.h,
            color: 0xffffff, text_size: cfg.pairing.title.text_size, align_h: align.CENTER_H, align_v: align.CENTER_V, text_style: text_style.WRAP, text: 'DayOne Orbit\nPairing PIN'
          })
          createWidget(widget.TEXT, {
            x: cfg.pairing.pin.x, y: cfg.pairing.pin.y, w: cfg.pairing.pin.w, h: cfg.pairing.pin.h,
            color: 0x00ff00, text_size: cfg.pairing.pin.text_size, align_h: align.CENTER_H, align_v: align.CENTER_V, text: pin
          })
          
          const statusText = createWidget(widget.TEXT, {
            x: cfg.pairing.status.x, y: cfg.pairing.status.y, w: cfg.pairing.status.w, h: cfg.pairing.status.h,
            color: 0xaaaaaa, text_size: cfg.pairing.status.text_size, align_h: align.CENTER_H, align_v: align.CENTER_V, text: 'Connecting to phone...'
          })

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
        createWidget(widget.TEXT, { x: 0, y: 0, w: cfg.screenW, h: cfg.screenH, color: 0xff0000, text_size: 20, align_h: align.CENTER_H, align_v: align.CENTER_V, text_style: text_style.WRAP, text: fatalErr ? fatalErr.toString() : 'Unknown Error' })
      }
    },
    
    onInit() {},
    onDestroy() {}
  })
)
