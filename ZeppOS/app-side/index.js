import { BaseSideService } from '@zeppos/zml/base-side'

const SUPABASE_URL = 'https://akkfouifxztnfwwiclwg.supabase.co'
const SUPABASE_ANON_KEY = 'sb_publishable_6FzrRSdmsH4arDhZS09PSQ_QK_I31DG'

AppSideService(
  BaseSideService({
    onInit() {},
    onRequest(req, res) {
      try {
        if (req.method === 'PAIR_WATCH') {
          const { pin } = req.params
          fetch({
            url: `${SUPABASE_URL}/rest/v1/watch_pairing_codes`,
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'apikey': SUPABASE_ANON_KEY,
              'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
              'Prefer': 'return=representation'
            },
            body: JSON.stringify({ pin_code: String(pin) })
          })
          .then(response => {
            if (response.status >= 400) return res(`API Error ${response.status}`, { success: false })
            res(null, { success: true })
          })
          .catch(err => { res(err ? err.toString() : 'Network err', { success: false }) })
        } else if (req.method === 'POLL_WATCH') {
          const { pin } = req.params
          fetch({
            url: `${SUPABASE_URL}/rest/v1/watch_pairing_codes?pin_code=eq.${pin}&select=*`,
            method: 'GET',
            headers: { 'apikey': SUPABASE_ANON_KEY, 'Authorization': `Bearer ${SUPABASE_ANON_KEY}` }
          })
          .then(response => {
             const resBody = typeof response.body === 'string' ? JSON.parse(response.body) : response.body
             res(null, { success: true, data: resBody })
          })
          .catch(err => { res(err ? err.toString() : 'Network err', { success: false }) })
        } else if (req.method === 'GET_PREFS') {
          const { access_token } = req.params
          fetch({
            url: `${SUPABASE_URL}/rest/v1/user_preferences?select=*`,
            method: 'GET',
            headers: { 'apikey': SUPABASE_ANON_KEY, 'Authorization': `Bearer ${access_token}` }
          })
          .then(response => {
             const resBody = typeof response.body === 'string' ? JSON.parse(response.body) : response.body
             let prefs = { water_goal: 2000, smokes_baseline: 20 }
             if (Array.isArray(resBody) && resBody.length > 0) {
               if (resBody[0].water_goal) prefs.water_goal = resBody[0].water_goal
               if (resBody[0].smokes_baseline) prefs.smokes_baseline = resBody[0].smokes_baseline
             }
             res(null, { success: true, data: prefs })
          })
          .catch(err => { res(err ? err.toString() : 'Network err', { success: false }) })
        } else if (req.method === 'GET_HABITS_TODAY') {
          const { access_token, habit_type } = req.params
          const now = new Date()
          const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString()

          fetch({
            url: `${SUPABASE_URL}/rest/v1/habits_logs?habit_type=eq.${habit_type}&logged_at=gte.${startOfToday}&select=*`,
            method: 'GET',
            headers: {
              'apikey': SUPABASE_ANON_KEY,
              'Authorization': `Bearer ${access_token}`
            }
          })
          .then(response => {
             const resBody = typeof response.body === 'string' ? JSON.parse(response.body) : response.body
             let total = 0
             let waterTotal = 0
             let coffeeTotal = 0
             let cigTotal = 0
             let heatTotal = 0

             if (Array.isArray(resBody)) {
               resBody.forEach(row => { 
                 const val = parseFloat(row.value) || 0
                 total += val
                 
                 let meta = {}
                 if (typeof row.metadata === 'string') {
                    try { meta = JSON.parse(row.metadata) } catch(e) {}
                 } else if (row.metadata) {
                    meta = row.metadata
                 }
                 
                 if (habit_type === 'water') {
                   const drinkType = meta.drink || ''
                   if (drinkType.includes('Coffee')) coffeeTotal += val
                   else waterTotal += val
                 } else if (habit_type === 'smokes') {
                   const sType = meta.type || ''
                   if (sType.includes('Heat') || sType.includes('Vape')) heatTotal += val
                   else cigTotal += val
                 }
               })
             }
             res(null, { success: true, data: { total, waterTotal, coffeeTotal, cigTotal, heatTotal } })
          })
          .catch(err => { res(err ? err.toString() : 'Network err', { success: false }) })
        } else if (req.method === 'GET_HABITS_WEEK') {
          const { access_token, habit_type } = req.params
          const now = new Date()
          const sevenDaysAgo = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 6).toISOString()

          fetch({
            url: `${SUPABASE_URL}/rest/v1/habits_logs?habit_type=eq.${habit_type}&is_deleted=eq.false&logged_at=gte.${sevenDaysAgo}&select=*`,
            method: 'GET',
            headers: {
              'apikey': SUPABASE_ANON_KEY,
              'Authorization': `Bearer ${access_token}`
            }
          })
          .then(response => {
             const resBody = typeof response.body === 'string' ? JSON.parse(response.body) : response.body
             // We return exactly 7 buckets for the histogram
             let weekBuckets = [0, 0, 0, 0, 0, 0, 0]
             
             if (Array.isArray(resBody)) {
               resBody.forEach(row => { 
                 const val = parseFloat(row.value) || 0
                 const logDate = new Date(row.logged_at)
                 // Calculate difference in days from exactly 6 days ago (which is bucket 0)
                 const diffTime = Math.abs(now.getTime() - logDate.getTime())
                 const diffDays = Math.floor(diffTime / (1000 * 60 * 60 * 24))
                 // Bucket 6 is today (diffDays == 0). Bucket 0 is 6 days ago (diffDays == 6).
                 const bucketIndex = 6 - diffDays
                 
                 if (bucketIndex >= 0 && bucketIndex <= 6) {
                   weekBuckets[bucketIndex] += val
                 }
               })
             }
             res(null, { success: true, data: weekBuckets })
          })
          .catch(err => { res(err ? err.toString() : 'Network err', { success: false }) })
        } else if (req.method === 'LOG_HABIT') {
          const { access_token, user_id, habit_type, value, unit, metadata } = req.params
          
          let bodyObj = {
            habit_type: habit_type,
            value: value,
            unit: unit,
            logged_at: new Date().toISOString(),
            metadata: metadata,
            is_deleted: false,
            user_id: user_id
          }
          
          fetch({
            url: `${SUPABASE_URL}/rest/v1/habits_logs`,
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'apikey': SUPABASE_ANON_KEY,
              'Authorization': `Bearer ${access_token}`,
              'Prefer': 'return=representation'
            },
            body: JSON.stringify(bodyObj)
          })
          .then(response => {
            if (response.status >= 400) return res(`API Error ${response.status}`, { success: false })
            res(null, { success: true })
          })
          .catch(err => { res(err ? err.toString() : 'Network err', { success: false }) })
        } else {
          res(null, { error: 'Unknown method' })
        }
      } catch (fatalErr) {
        res(fatalErr ? fatalErr.toString() : 'Fatal error', { success: false })
      }
    }
  })
)
