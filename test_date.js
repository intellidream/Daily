const now = new Date('2026-09-03T09:00:00+03:00') // 9 AM Romania
const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString()
console.log(startOfToday)
