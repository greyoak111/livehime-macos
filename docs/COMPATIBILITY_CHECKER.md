# 公开资源兼容性观察工具

`scripts/compatibility-check.py` 只使用 Python 标准库，默认离线。它支持公开资源观察与
快照比较，不登录、不上传数据、不触发开关播，不在后台定时运行。

```sh
# 全部是内置虚拟数据，不联网
python3 scripts/compatibility-check.py snapshot --output /tmp/livehime-fixture.json

# 手动显式联网：只读取三个固定的公开 HTTPS 地址
python3 scripts/compatibility-check.py snapshot --online --output /tmp/livehime-public-now.json

# 比较两次相同来源的观察
python3 scripts/compatibility-check.py compare /tmp/livehime-public-before.json /tmp/livehime-public-now.json

# 使用自备虚拟样本：固定文件名 liveVersion.json、miniLogin.html、faceAuth.html
python3 scripts/compatibility-check.py snapshot --fixture-dir /tmp/my-livehime-fixtures
```

网络请求不带 Cookie 或 Authorization，不加载 JS、不跟随重定向。地址由代码中的精确清单
限制，清单包括 `api.live.bilibili.com` 的公开版本接口，以及 `live.bilibili.com` 的 mini-login-v2
和 bilili-page-face-auth 两个入口。单次请求超时 8 秒，响应上限 2 MiB；网络错误仅输出固定分类，
不会把可能包含 URL/路径的异常文本写进报告。工具沿用系统 Python 的正常 TLS 校验。

快照包含 HTTP 状态、响应长度、HTML/JSON SHA-256、脚本/CSS 引用数量和引用指纹，以及公开
版本号/build；不保存响应原文或完整脚本 URL。版本字段必须满足数字版本格式，无法识别的
结构报错。页面检查只验证基础 HTML 和外链脚本/样式结构；不会断言 Vue 已挂载或验证组件已就绪。

`compare` 拒绝把虚拟数据和官方观察混为一谈。缺资源、没有有效旧基线、HTTP 错误、版本/build
或指纹变化会得到 `review_required`。`no_change_observed` 只表示此次没有观察到变化，绝不意味着
账号资格、验证流程、服务端兼容性或推流已通过测试。

`compatibility/manifest.json` 区分历史测试记录、公开观察字段和指纹基线。未知基线保持 `null`；
工具不会自动将某次观察提升为“已通过测试”，也不会覆盖清单。观察与差异报告由维护者审阅后，
再决定补哪个 fixture、检查哪个桥接方法、是否安排人工测试。

退出码：snapshot 全部资源可解析为 0，任一观察失败为 1；输入/输出错误为 2。compare 正常
生成报告返回 0，是否有变化读取报告的 `decision`。本轮未配置定时任务或自动账号探测。
