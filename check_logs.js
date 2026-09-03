const fs = require('fs')
const key = process.env.ANON_KEY || fs.readFileSync('ZeppOS/app-side/index.js', 'utf8').match(/SUPABASE_ANON_KEY = '([^']+)'/)[1]
const SUPABASE_URL = 'https://akkfouifxztnfwwiclwg.supabase.co'

async function check() {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/habits_logs?select=*&order=created_at.desc&limit=5`, {
    headers: { 'apikey': key, 'Authorization': `Bearer ${key}` }
  })
  console.log(res.status, await res.text())
}
check()
