# First family onboarding commit

The new-family path commits one child profile and the chosen family member together in an isolated SwiftData context. Only successful save changes current identity, child name, role, widgets or the completed flag. A failure keeps the wizard and its input, shows a recoverable error and leaves the shared UI context untouched. Stable draft IDs make repeated completion idempotent. Existing committed child profiles and matching members are reused without overwriting their fields.

The primary action and keyboard Done end text input without clearing it. Back returns to the previous step without discarding name, birthday or relationship choices. Joining an existing family creates neither a local child nor a member: it retains the existing role/login handoff behavior. Cancelling the login sheet does not manufacture a new family.

Acceptance includes real unseeded first-launch wizard navigation, one-shot persistence rejection, visible error and retained drafts, retry, and existing-family login cancellation. Disk-backed helper tests reopen the store and verify counts/identity, unrelated pending edits and reuse. No production schema is changed.

首次加入家庭的账号sheet提供明确「稍后登录」动作；关闭只退出登录界面，不新建本地家庭、不清除选择的家庭角色，也不登录或保存凭据。原生iPad全屏中部swipeDown未关闭是本次复现路径，验收改用实际可见退出动作并保0/0实体读回。
