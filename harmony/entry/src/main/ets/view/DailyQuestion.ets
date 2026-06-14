// MARK: - 每日一问（对照 iOS Features/Capture/DailyQuestion.swift）
// 让「不知道记什么」消失：本地题库按布布月龄分桶，以日期为种子轮换，全家同一天看到同一题。
// 零后端、零 AI 依赖。

export class DailyQuestion {
  // 按月龄分桶的问题库（宁少勿滥，覆盖常见成长阶段）。
  private static readonly infant: string[] = [   // 0–12 月
    '今天布布最像哪种小动物？',
    '她今天发出的最可爱的声音是什么？',
    '今天她盯着什么看了好久？',
    '她今天第一次尝了什么味道？',
    '今天谁把她逗笑了，怎么逗的？',
    '她今天睡得香吗，什么姿势？',
    '今天她的小手抓住了什么不肯放？',
    '她今天最讨厌的瞬间是什么？'
  ];
  private static readonly toddler: string[] = [  // 13–36 月
    '她今天发明了什么新词？',
    '今天她最得意的一件事是什么？',
    '她现在最讨厌什么？',
    '今天她模仿了谁，像不像？',
    '她今天最坚持要做的事是什么？',
    '今天她说的哪句话把你逗乐了？',
    '她今天交了新朋友吗，叫什么？',
    '今天她最舍不得放下的玩具是哪个？'
  ];
  private static readonly child: string[] = [    // 37 月以上
    '她今天问了什么让你答不上来的问题？',
    '今天她的梦想是什么（可能每天都变）？',
    '她今天最骄傲的作品是什么？',
    '今天她说了什么暖心的话？',
    '她今天最害怕又最想挑战的是什么？',
    '今天她最想和谁一起玩？',
    '她今天学会了什么新本领？',
    '今天她做了什么小大人的事？'
  ];

  // 取「今天」的问题：先按月龄选桶，再以当天日期为种子在桶内轮换。
  // iOS: birthday: Date? → 这里用 birthdayMs: number | undefined（沿用 epoch-ms 约定）。
  static todays(birthdayMs: number | undefined, atMs: number = Date.now()): string {
    const bank: string[] = DailyQuestion.bucket(birthdayMs, atMs);
    // iOS: Calendar.ordinality(of:.day,in:.era) → 以天为序数；这里用自纪元起的天数。
    const day: number = Math.floor(atMs / 86400000);
    return bank[Math.abs(day) % bank.length];
  }

  private static bucket(birthdayMs: number | undefined, atMs: number): string[] {
    if (birthdayMs === undefined) {
      return DailyQuestion.toddler;
    }
    const now = new Date(atMs);
    const bd = new Date(birthdayMs);
    const months: number =
      (now.getFullYear() - bd.getFullYear()) * 12 + (now.getMonth() - bd.getMonth());
    if (months < 13) {
      return DailyQuestion.infant;
    } else if (months < 37) {
      return DailyQuestion.toddler;
    }
    return DailyQuestion.child;
  }
}
