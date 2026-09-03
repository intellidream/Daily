const fs = require('fs')
const key = process.env.ANON_KEY

async function check() {
  const res = await fetch(`https://yfttdzuvfhzfbnjofxqp.supabase.co/rest/v1/habits_logs?select=id&limit=1`, {
    headers: { 'apikey': key, 'Authorization': `Bearer ${key}` }
  })
  console.log(res.status, await res.text())
}
check()
