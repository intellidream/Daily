import { BaseSideService } from '@zeppos/zml/base-side'

const SUPABASE_URL = 'https://akkfouifxztnfwwiclwg.supabase.co'
const SUPABASE_ANON_KEY = 'sb_publishable_6FzrRSdmsH4arDhZS09PSQ_QK_I31DG'

AppSideService(
  BaseSideService({
    onInit() {
      console.log('App Side Service Init')
    },
    
    onRequest(req, res) {
      console.log('Received request from Watch:', req.method)
      
      if (req.method === 'PAIR_WATCH') {
        const { pin } = req.params
        
        // 1. Send the PIN to Supabase
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
            pin_code: pin,
            expires_at: new Date(Date.now() + 15 * 60000).toISOString()
          })
        })
        .then(() => {
          // 2. Start polling for the token
          let attempts = 0
          const maxAttempts = 60 // 3 minutes total if polling every 3s
          
          const poll = () => {
            fetch({
              url: `${SUPABASE_URL}/rest/v1/watch_pairing_codes?pin_code=eq.${pin}&select=*`,
              method: 'GET',
              headers: {
                'apikey': SUPABASE_ANON_KEY,
                'Authorization': `Bearer ${SUPABASE_ANON_KEY}`
              }
            })
            .then(response => {
              const data = typeof response.body === 'string' ? JSON.parse(response.body) : response.body;
              if (data && data.length > 0 && data[0].claimed === true && data[0].access_token) {
                // Success! The desktop app has inserted the tokens
                res(null, { success: true, tokens: data[0] })
              } else {
                // Not claimed yet
                attempts++
                if (attempts < maxAttempts) {
                  setTimeout(poll, 3000)
                } else {
                  res('Pairing timeout', { success: false })
                }
              }
            })
            .catch(err => {
              res(err.toString(), { success: false })
            })
          }
          
          poll()
        })
        .catch(err => {
          res(err.toString(), { success: false })
        })
      } else {
        res(null, { error: 'Unknown method' })
      }
    },

    onRun() {
      console.log('App Side Service Run')
    },

    onDestroy() {
      console.log('App Side Service Destroy')
    }
  })
)
