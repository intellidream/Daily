import { createWidget, deleteWidget, widget, prop, align, text_style } from '@zos/ui'
import { log } from '@zos/utils'
import { BasePage } from '@zeppos/zml/base-page'
import { back } from '@zos/router'
import { setScrollMode, SCROLL_MODE_FREE } from '@zos/page'
import { getDeviceInfo, SCREEN_SHAPE_ROUND } from '@zos/device'
import { readFileSync, statSync } from '@zos/fs'
import { Vibrator, VIBRATOR_SCENE_SHORT_STRONG, VIBRATOR_SCENE_DURATION } from '@zos/sensor'

const logger = log.getLogger('dayone-orbit-logs')

let vibratorInstance = null

function ensureVibrator() {
  if (!vibratorInstance) {
    try {
      if (typeof Vibrator !== 'undefined') {
        vibratorInstance = new Vibrator()
      }
    } catch (e) {
      try {
        vibratorInstance = Vibrator()
      } catch (e2) {}
    }
  }
  return vibratorInstance
}

const triggerHaptic = (sceneType = 'habit') => {
  try {
    const v = ensureVibrator()
    if (!v) return

    const mode = sceneType === 'nav' ? (VIBRATOR_SCENE_SHORT_STRONG || 25) : (VIBRATOR_SCENE_DURATION || 28)
    
    try {
      if (typeof v.setMode === 'function') {
        try { v.setMode({ mode }) } catch(e1) { v.setMode(mode) }
      }
    } catch (e2) {}

    try {
      v.start({ mode })
    } catch (e3) {
      try { v.start() } catch(e4) {}
    }

    setTimeout(() => {
      try {
        if (v && typeof v.stop === 'function') v.stop()
      } catch (eStop) {}
    }, 500)
  } catch (err) {}
}

function loadFileStr(filename) {
  try {
    const stat = statSync({ path: filename })
    if (stat) return readFileSync({ path: filename, options: { encoding: 'utf8' } })
  } catch(e) {}
  return ''
}

function formatTime(isoStr) {
  try {
    const d = new Date(isoStr)
    if (isNaN(d.getTime())) return ''
    const h = String(d.getHours()).padStart(2, '0')
    const m = String(d.getMinutes()).padStart(2, '0')
    return `${h}:${m}`
  } catch(e) {
    return ''
  }
}

Page(
  BasePage({
    onInit(param) {
      this.ctx = null
      if (param) {
        try {
          this.ctx = typeof param === 'string' ? JSON.parse(param) : param
        } catch(e) {}
      }
      if (!this.ctx) {
        try {
          const raw = loadFileStr('logs_context.json')
          if (raw) this.ctx = JSON.parse(raw)
        } catch(e) {}
      }
      ensureVibrator()
    },

    build() {
      const self = this
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

      try {
        setScrollMode({ mode: SCROLL_MODE_FREE })
      } catch(e) {
        logger.error('setScrollMode error', e)
      }

      const ctx = this.ctx || {}
      const habitType = ctx.habitType || 'water'
      const isWater = habitType === 'water'
      const dayOffset = ctx.dayOffset || 0
      const dateLabel = ctx.dateLabel || 'Today'
      const accessToken = ctx.accessToken || loadFileStr('token.txt')
      const userId = ctx.userId || loadFileStr('userid.txt')
      let logs = Array.isArray(ctx.logs) ? [...ctx.logs] : []

      // Layout coordinates
      const headerY = isRound ? 32 : 18
      const headerH = 34
      const subtitleY = isRound ? 68 : 52
      const subtitleH = 22
      const startY = isRound ? 104 : 84
      const cardW = isRound ? 414 : 358
      const cardX = Math.floor((screenW - cardW) / 2)
      const cardH = 64
      const cardSpacing = 10

      // Top Back Button
      createWidget(widget.BUTTON, {
        x: isRound ? 34 : 14,
        y: headerY,
        w: 40,
        h: 40,
        radius: 20,
        normal_color: 0x222222,
        press_color: 0x111111,
        text: '◀',
        color: isWater ? 0x00aaff : 0xff5555,
        text_size: 18,
        click_func: () => {
          triggerHaptic('nav')
          back()
        }
      })

      // Top Header Title
      createWidget(widget.TEXT, {
        x: 0,
        y: headerY,
        w: screenW,
        h: headerH,
        color: isWater ? 0x00aaff : 0xff5555,
        text_size: isRound ? 22 : 20,
        align_h: align.CENTER_H,
        align_v: align.CENTER_V,
        text: isWater ? '💧 Water Logs' : '🔥 Smoke Logs'
      })

      // Date & Entries Subtitle
      const subtitleText = createWidget(widget.TEXT, {
        x: 0,
        y: subtitleY,
        w: screenW,
        h: subtitleH,
        color: 0x888888,
        text_size: 14,
        align_h: align.CENTER_H,
        align_v: align.CENTER_V,
        text: `${logs.length} ${logs.length === 1 ? 'entry' : 'entries'} • ${dateLabel}`
      })

      let logItemWidgets = []
      let confirmOverlayWidgets = []

      const hideConfirm = () => {
        confirmOverlayWidgets.forEach(w => {
          try { deleteWidget(w) } catch(e) {}
        })
        confirmOverlayWidgets = []
      }

      const showConfirm = (title, details, onConfirm) => {
        hideConfirm()
        const bg = createWidget(widget.FILL_RECT, {
          x: 0,
          y: 0,
          w: screenW,
          h: screenH,
          color: 0x000000
        })

        const titleW = createWidget(widget.TEXT, {
          x: 20,
          y: isRound ? 95 : 75,
          w: screenW - 40,
          h: 36,
          color: 0xffffff,
          text_size: 20,
          align_h: align.CENTER_H,
          align_v: align.CENTER_V,
          text: title
        })

        const descW = createWidget(widget.TEXT, {
          x: 20,
          y: isRound ? 135 : 115,
          w: screenW - 40,
          h: 48,
          color: 0xaaaaaa,
          text_size: 15,
          align_h: align.CENTER_H,
          align_v: align.CENTER_V,
          text_style: text_style.WRAP,
          text: details
        })

        const delBtn = createWidget(widget.BUTTON, {
          x: isRound ? 70 : 45,
          y: isRound ? 220 : 195,
          w: isRound ? 340 : 300,
          h: 56,
          radius: 28,
          normal_color: 0x8b0000,
          press_color: 0xff0000,
          text: 'Delete Log',
          color: 0xffffff,
          text_size: 18,
          click_func: () => {
            hideConfirm()
            onConfirm()
          }
        })

        const cancelBtn = createWidget(widget.BUTTON, {
          x: isRound ? 70 : 45,
          y: isRound ? 290 : 265,
          w: isRound ? 340 : 300,
          h: 56,
          radius: 28,
          normal_color: 0x222222,
          press_color: 0x111111,
          text: 'Cancel',
          color: 0xaaaaaa,
          text_size: 18,
          click_func: () => {
            triggerHaptic('nav')
            hideConfirm()
          }
        })

        confirmOverlayWidgets = [bg, titleW, descW, delBtn, cancelBtn]
      }

      const deleteLog = (logItem) => {
        triggerHaptic('habit')
        self.request({
          method: 'DELETE_HABIT_LOG',
          params: {
            access_token: accessToken,
            log_id: logItem.id
          }
        }).then(res => {
          logs = logs.filter(item => item.id !== logItem.id)
          renderLogs(logs)
          if (subtitleText) {
            subtitleText.setProperty(prop.TEXT, `${logs.length} ${logs.length === 1 ? 'entry' : 'entries'} • ${dateLabel}`)
          }
        }).catch(err => {
          logger.error('deleteLog error', err)
        })
      }

      const renderLogs = (items) => {
        logItemWidgets.forEach(w => {
          try { deleteWidget(w) } catch(e) {}
        })
        logItemWidgets = []

        if (!items || items.length === 0) {
          const emptyWidget = createWidget(widget.TEXT, {
            x: 20,
            y: isRound ? 190 : 170,
            w: screenW - 40,
            h: 80,
            color: 0x777777,
            text_size: 16,
            align_h: align.CENTER_H,
            align_v: align.CENTER_V,
            text_style: text_style.WRAP,
            text: 'No logs recorded for this day.'
          })
          logItemWidgets.push(emptyWidget)
          return
        }

        items.forEach((item, index) => {
          const y = startY + index * (cardH + cardSpacing)
          
          let icon = '💧'
          let displayType = 'Water'
          let val = Math.round(item.value) || 0

          if (isWater) {
            const isCoffee = (item.type || '').includes('Coffee')
            icon = isCoffee ? '☕' : '💧'
            const isSmall = (item.type || '') === 'Small Water'
            displayType = isCoffee ? 'Coffee' : (isSmall ? 'Small' : 'Large')
          } else {
            const isHeat = (item.type || '').includes('Heat') || (item.type || '').includes('Vape')
            icon = isHeat ? '⚡' : '🔥'
            displayType = isHeat ? 'Heat' : 'Cig'
          }

          const titleStr = isWater ? `${val} ml ${displayType}` : `${val} ${displayType}`
          const timeStr = formatTime(item.logged_at)

          // Card Background
          const cardBg = createWidget(widget.FILL_RECT, {
            x: cardX,
            y: y,
            w: cardW,
            h: cardH,
            radius: 14,
            color: 0x1c1c1e
          })

          // Icon
          const iconW = createWidget(widget.TEXT, {
            x: cardX + 12,
            y: y,
            w: 36,
            h: cardH,
            color: 0xffffff,
            text_size: 20,
            align_h: align.CENTER_H,
            align_v: align.CENTER_V,
            text: icon
          })

          // Value & Type
          const textTitle = createWidget(widget.TEXT, {
            x: cardX + 52,
            y: y + 10,
            w: cardW - 110,
            h: 24,
            color: 0xffffff,
            text_size: 16,
            align_h: align.LEFT,
            align_v: align.CENTER_V,
            text: titleStr
          })

          // Time
          const textTime = createWidget(widget.TEXT, {
            x: cardX + 52,
            y: y + 34,
            w: cardW - 110,
            h: 20,
            color: 0x888888,
            text_size: 13,
            align_h: align.LEFT,
            align_v: align.CENTER_V,
            text: timeStr
          })

          // Delete Button
          const delBtn = createWidget(widget.BUTTON, {
            x: cardX + cardW - 50,
            y: y + 12,
            w: 40,
            h: 40,
            radius: 20,
            normal_color: 0x2c1010,
            press_color: 0x501515,
            text: '🗑️',
            color: 0xff3b30,
            text_size: 16,
            click_func: () => {
              triggerHaptic('nav')
              showConfirm('Delete Log?', `${titleStr} (${timeStr})`, () => deleteLog(item))
            }
          })

          logItemWidgets.push(cardBg, iconW, textTitle, textTime, delBtn)
        })

        // Bottom padding spacer so last card scrolls well above screen edge
        const bottomSpacer = createWidget(widget.TEXT, {
          x: 0,
          y: startY + items.length * (cardH + cardSpacing),
          w: screenW,
          h: 60,
          color: 0x000000,
          text: ''
        })
        logItemWidgets.push(bottomSpacer)
      }

      // Render initial cached logs immediately
      renderLogs(logs)

      // Re-fetch fresh data from phone/server
      if (accessToken) {
        self.request({
          method: 'GET_HABITS_TODAY',
          params: {
            access_token: accessToken,
            user_id: userId,
            habit_type: habitType,
            day_offset: dayOffset
          }
        }).then(res => {
          if (res && res.success && res.data && Array.isArray(res.data.logs)) {
            logs = res.data.logs
            renderLogs(logs)
            if (subtitleText) {
              subtitleText.setProperty(prop.TEXT, `${logs.length} ${logs.length === 1 ? 'entry' : 'entries'} • ${dateLabel}`)
            }
          }
        }).catch(err => {
          logger.error('fresh fetch error in logs page', err)
        })
      }
    },

    onDestroy() {
      try {
        if (vibratorInstance && typeof vibratorInstance.stop === 'function') {
          vibratorInstance.stop()
        }
      } catch (e) {}
    }
  })
)
