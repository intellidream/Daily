import { BaseSideService } from '@zeppos/zml/base-side'

const SUPABASE_URL = 'https://akkfouifxztnfwwiclwg.supabase.co'
const SUPABASE_ANON_KEY = 'sb_publishable_6FzrRSdmsH4arDhZS09PSQ_QK_I31DG'

AppSideService(
  BaseSideService({
    onInit() {
      console.log('App Side Service Init')
    },
    
    onRequest(req, res) {
      console.log('Received request from Watch:', req?.method)
      
      try {
        if (req.method === 'PAIR_WATCH') {
          const { pin } = req.params
          console.log('Starting fetch for pin:', pin)

          // Zepp OS 3.0 fetch expects a SINGLE object argument
          fetch({
            url: `${SUPABASE_URL}/rest/v1/watch_pairing_codes`,
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'apikey': SUPABASE_ANON_KEY,
              'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
              'Prefer': 'return=representation'
            },
            body: JSON.stringify({
              pin_code: String(pin)
            })
          })
          .then((response) => {
            console.log('Fetch POST completed with status:', response.status)
            if (response.status >= 400) {
               return res(`API Error ${response.status}`, { success: false })
            }
            
            res(null, { success: true })
          })
          .catch(err => {
            console.log('Fetch POST failed', err)
            res(err ? err.toString() : 'Unknown POST network err', { success: false })
          })
        } else if (req.method === 'POLL_WATCH') {
          const { pin } = req.params
          
          fetch({
            url: `${SUPABASE_URL}/rest/v1/watch_pairing_codes?pin_code=eq.${pin}&select=*`,
            method: 'GET',
            headers: {
              'apikey': SUPABASE_ANON_KEY,
              'Authorization': `Bearer ${SUPABASE_ANON_KEY}`
            }
          })
          .then(response => {
             const resBody = typeof response.body === 'string' ? JSON.parse(response.body) : response.body
             res(null, { success: true, data: resBody })
          })
          .catch(err => {
             res(err ? err.toString() : 'Unknown GET network err', { success: false })
          })
        } else if (req.method === 'GET_HABITS_TODAY') {
          const { access_token, habit_type } = req.params
          const now = new Date()
          const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString()

          fetch({
            url: `${SUPABASE_URL}/rest/v1/habits_logs?habit_type=eq.${habit_type}&logged_at=gte.${startOfToday}&select=value`,
            method: 'GET',
            headers: {
              'apikey': SUPABASE_ANON_KEY,
              'Authorization': `Bearer ${access_token}`
            }
          })
          .then(response => {
             const resBody = typeof response.body === 'string' ? JSON.parse(response.body) : response.body
             let total = 0
             if (Array.isArray(resBody)) {
               resBody.forEach(row => { total += (row.value || 0) })
             }
             res(null, { success: true, data: { total } })
          })
          .catch(err => {
             res(err ? err.toString() : 'Unknown GET network err', { success: false })
          })
        } else if (req.method === 'LOG_HABIT') {
          const { access_token, user_id, habit_type, value, unit, metadata } = req.params

          fetch({
            url: `${SUPABASE_URL}/rest/v1/habits_logs`,
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'apikey': SUPABASE_ANON_KEY,
              'Authorization': `Bearer ${access_token}`,
              'Prefer': 'return=representation'
            },
            body: JSON.stringify({
              user_id: user_id,
              habit_type: habit_type,
              value: value,
              unit: unit,
              logged_at: new Date().toISOString(),
              metadata: metadata
            })
          })
          .then(response => {
            if (response.status >= 400) {
               return res(`API Error ${response.status}`, { success: false })
            }
            res(null, { success: true })
          })
          .catch(err => {
            res(err ? err.toString() : 'Unknown POST network err', { success: false })
          })
        } else {
          res(null, { error: 'Unknown method' })
        }
      } catch (fatalErr) {
        console.log('Fatal error in onRequest', fatalErr)
        res(fatalErr ? fatalErr.toString() : 'Fatal unknown error', { success: false })
      }
    }
  })
)
