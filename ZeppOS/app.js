import { BaseApp } from '@zeppos/zml/base-app'

App(
  BaseApp({
    globalData: {
      accessToken: null,
      refreshToken: null
    },
    onCreate(options) {
      console.log('App onCreate');
    },
    onDestroy(options) {
      console.log('App onDestroy');
    }
  })
)
