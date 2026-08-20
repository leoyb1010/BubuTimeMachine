export type BackHandler = () => boolean;

interface BackRegistration {
  key: string;
  priority: number;
  order: number;
  handler: BackHandler;
}

// 系统返回一次只交给一个最深层处理器，避免全局广播被多个嵌套页面同时消费。
export class BackDispatcher {
  static readonly shared = new BackDispatcher();
  private registrations: Map<string, BackRegistration> = new Map();
  private order: number = 0;

  register(key: string, priority: number, handler: BackHandler): void {
    this.order += 1;
    this.registrations.set(key, { key, priority, order: this.order, handler });
  }

  unregister(key: string): void { this.registrations.delete(key); }

  handleBack(): boolean {
    const candidates = Array.from(this.registrations.values())
      .sort((a: BackRegistration, b: BackRegistration): number =>
        b.priority - a.priority || b.order - a.order);
    for (const candidate of candidates) {
      if (candidate.handler()) return true;
      this.registrations.delete(candidate.key);
    }
    return false;
  }

  clear(): void { this.registrations.clear(); }
}
