# OneDay Companion（伴生服务）

双容器收口的伴生容器工程：监督者（PID 1）＋front（面板与 /api/companion）＋五桥模块，
基础镜像钉版 hermes-agent:v0.23.0。规格：~/workspace/oneday-design-review/companion-service-design-20261110.md。

- 构建：`docker build -t oneday/companion:1.0.0 .`（需基础镜像在位）
- 配置：复制 `companion.env.example` 为 `companion.env`（0600），逐段填钥；密码哈希用
  `python3 front/front.py --hash-password '你的密码'` 生成
- 本地验（一条命令全栈）：`python3 tests/run_local_stack.py`
- M0 验证报告：`M0-REPORT.md`
