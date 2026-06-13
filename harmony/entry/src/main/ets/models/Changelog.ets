// MARK: - 版本更新记录（对齐 iOS 1.2.0）
export interface ReleaseNote {
  version: string;
  date: string;
  title: string;
  highlights: string[];
}

export const CHANGELOG: ReleaseNote[] = [
  {
    version: '1.2.0',
    date: '2026-06-13',
    title: '家人各自登录 · 桌面小组件更好看',
    highlights: [
      '新增「更新记录」：每次更新都能在设置里查看',
      '家人可以各自注册登录（用家庭码加入），署名更清楚',
      '服务器已内置，不用再手动填地址，装上即用',
      '桌面小组件加上布布头像，支持小/中/大三种尺寸',
      '设置页底部显示当前版本号'
    ]
  },
  {
    version: '1.1.9',
    date: '2026-06-13',
    title: '更丝滑 · 系统级集成 · 性别血型补全',
    highlights: [
      'ProMotion 设备解锁 120Hz，操作更跟手丝滑',
      '桌面/锁屏小组件、灵动岛、控制中心、Siri 全面接入',
      '可在档案里填写性别、血型，身份卡翻面查看',
      '修复上传背景照片把页面撑变形的问题',
      '记录保存、里程碑点亮等动效升级'
    ]
  }
];
