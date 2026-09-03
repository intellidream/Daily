const SUPABASE_URL = 'https://yfttdzuvfhzfbnjofxqp.supabase.co'
const fs = require('fs')
const key = fs.readFileSync('ZeppOS/app-side/index.js', 'utf8').match(/SUPABASE_ANON_KEY = '([^']+)'/)[1]

async function test() {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/update_modified_column`, {
    method: 'POST',
    headers: { 'apikey': key, 'Authorization': `Bearer ${key}` }
  })
  const text = await res.text()
  console.log(res.status, text)
}
test()
