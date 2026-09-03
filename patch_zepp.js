const fs = require('fs');
const file = '/Users/mihai/Source/Daily/ZeppOS/app-side/index.js';
let content = fs.readFileSync(file, 'utf8');

// Fix GET_HABITS_WEEK Date logic
content = content.replace(
`const logDate = new Date(row.logged_at)
                 // Calculate difference in days from exactly 6 days ago (which is bucket 0)
                 const diffTime = Math.abs(now.getTime() - logDate.getTime())
                 const diffDays = Math.floor(diffTime / (1000 * 60 * 60 * 24))`,
`const logDate = new Date(row.logged_at)
                 const todayAtMidnight = new Date(now.getFullYear(), now.getMonth(), now.getDate());
                 const logDateAtMidnight = new Date(logDate.getFullYear(), logDate.getMonth(), logDate.getDate());
                 const diffTime = Math.abs(todayAtMidnight.getTime() - logDateAtMidnight.getTime());
                 const diffDays = Math.round(diffTime / (1000 * 60 * 60 * 24));`
);

// Fix LOG_HABIT metadata format
content = content.replace(
`metadata: typeof metadata === 'string' ? metadata : JSON.stringify(metadata)`,
`metadata: typeof metadata === 'string' ? JSON.parse(metadata) : metadata`
);

fs.writeFileSync(file, content);
