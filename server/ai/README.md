# 布布时光机 · AI 伴生服务

自托管 FastAPI，App 端 `BubuAIService` 调用本服务，本服务再调 LLM（默认 DeepSeek，OpenAI 兼容协议）。
换模型 = 改本服务 `.env`，App 一行不改。

## 环境要求

- **Python ≥ 3.9**（代码刻意保持 3.9 兼容：Pydantic 模型一律 `Optional[...]` 写法，勿改成 `X | None`）
- 依赖见 `requirements.txt`；语音转写可选装 `faster-whisper`

## 启动

```bash
cp .env.example .env   # 填 DEEPSEEK_API_KEY 与 AI_API_KEY（必填，fail-closed）
./start_ai.sh          # 自动建 venv、装依赖、起 uvicorn（默认 :8000）
```

## 接口

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/rewrite-first-person` | 父母视角 → 布布第一人称日记 |
| POST | `/classify` | 记录的事件/地点/标签归类 |
| POST | `/detect-first-time` | 判断"是否人生第一次" |
| POST | `/movie-narration` | 年度成长电影旁白稿 |
| POST | `/parse-natural-capture` | 一句话 → 多条结构化记录（疫苗/成长/餐食/睡眠…）；LLM 输出服务端逐条清洗，敏感域强制 `needs_confirmation` |
| POST | `/transcribe` | 语音转写（需 faster-whisper） |
| GET | `/health` | 健康检查；带正确 `X-API-Key` 时附 `parse_stats`（解析 warnings 累计，监控 LLM 输出漂移） |

业务路由一律要求 `X-API-Key` 请求头 + 每 IP 限流（`AI_RATE_LIMIT_PER_MINUTE`，默认 30/分钟）。

## 测试

```bash
pip install -r requirements-dev.txt
pytest tests -q                    # 标准跑法
python3 tests/test_parse.py        # 无 pytest 的环境直跑（自动 stub 缺失依赖）
```

## 验收样例（部署后跑一遍）

```bash
KEY=你的AI_API_KEY
for t in "6月20日布布打了麻腮风疫苗" "今天身高82cm体重10.6kg" \
         "中午吃了南瓜米糊半碗，下午喝水120ml" "昨晚9点睡早上7点醒" \
         "今天咳嗽，体温37.8" "第一次自己扶着沙发站起来了"; do
  curl -s -X POST localhost:8000/parse-natural-capture \
    -H "Content-Type: application/json" -H "X-API-Key: $KEY" \
    -d "{\"text\":\"$t\",\"childName\":\"布布\",\"timezone\":\"Asia/Shanghai\",\"referenceDate\":\"$(date -Iseconds)\"}" | head -c 300; echo
done
```
