App({
  globalData: {
    supabaseUrl: "https://your-supabase-url.supabase.co",
    supabaseAnonKey: "your-anon-key",
    accessToken: null,
    refreshToken: null
  },
  onCreate(options) {
    console.log('App onCreate');
    // Load tokens from File System if they exist
    this.loadTokens();
  },
  onDestroy(options) {
    console.log('App onDestroy');
  },
  loadTokens() {
    // TODO: Use @zos/fs to read saved tokens
    console.log('Tokens loaded from local storage');
  }
})
