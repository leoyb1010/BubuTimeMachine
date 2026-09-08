export function capsuleVersion(bytes: Uint8Array): number {
  if (bytes.length >= 4 && bytes[0] === 0x42 && bytes[1] === 0x54 && bytes[2] === 0x43) {
    if (bytes[3] === 0x33) return 3;
    if (bytes[3] === 0x32) return 2;
  }
  return 1;
}

export function requireCapsuleVersion(bytes: Uint8Array, minimumVersion: number): void {
  if (minimumVersion >= 3 && capsuleVersion(bytes) < 3) {
    throw new Error('加密版本不一致，已保护这封信，请核对原始备份');
  }
}

export function rememberCapsuleVersion(local: number | undefined, remote: number | undefined): number {
  const before = local !== undefined && Number.isFinite(local) ? local : 0;
  const after = remote !== undefined && Number.isFinite(remote) ? remote : 0;
  return Math.max(before, after);
}
