const now = new Date()
const sevenDaysAgo = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 6).toISOString()
console.log(sevenDaysAgo)
