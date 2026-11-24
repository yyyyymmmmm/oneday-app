# Hermes 服务端语音样本留档（H2-a，台账 159）

DTO 冻结依据：H2-0 探活（pkg-hermes-voice-probe-20261120）＋开通复探
（pkg-hermes-voice-enable-20261120）。样本为现役实例 v0.23.0 实测形态；
speak 的 data_url 载荷只留形态与量级（真实音频不入仓）。

## GET /api/audio/voice-config（200，开通前后逐字不变）

```json
{
  "ok": true,
  "stt": {"mode": "relay", "reason": "command/plugin provider", "streaming": false},
  "tts": {"mode": "relay", "reason": "provider 'edge' has no client wire"}
}
```

注：tts.reason 是 relay 拓扑描述、不是可用性标志——开通后 speak 已 200，
本字段仍逐字不变。可用性判定口径见 OneDayCore.VoiceSpeech（组合字段＋
speak 实调精修）。

## POST /api/audio/speak（200，开通复探实测）

请求：`{"text": "你好，这是朗读测试"}`

```json
{
  "ok": true,
  "data_url": "data:audio/mpeg;base64,//Nkx…（15,696 字节 MP3 的 base64）",
  "mime_type": "audio/mpeg",
  "provider": "edge"
}
```

耗时：冷 1.58s／热 1.92s（短句）。失败：400 `{"detail": "…"}`——未开通
时 detail 含「No TTS provider available」；空文本 400「Text is required」。

## GET /api/audio/elevenlabs/voices（200，现役未配该 provider）

```json
{"available": false, "voices": []}
```

注：speak 的实际合成 provider 是 edge，与本端点不是同一家——音色展示
以 speak 回执的 provider 为准（探活 §2.4）。
