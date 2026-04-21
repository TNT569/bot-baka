# --- 第一阶段：构建环境 ---
FROM python:3.14 AS builder

# 安装 uv (直接用官方二进制，快到飞起)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /build

# 环境变量：强制 uv 在构建时不生成 pyc，减小体积
ENV UV_COMPILE_BYTECODE=0
ENV UV_HTTP_TIMEOUT=300

COPY pyproject.toml uv.lock ./

# 1. 关键：直接用 uv 同步依赖到 /build/.venv
# 它会根据当前架构（ARM）自动处理你 pyproject.toml 里的 markers
# 并且会自动去你定义的 pytorch-cpu 索引找货
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project

# 2. 生成 nb-cli 的入口文件 (保持你原有的逻辑)
RUN python -m uv tool run --no-cache --from nb-cli nb generate -f /tmp/bot.py


# --- 第二阶段：生产镜像 ---
FROM python:3.14-slim

WORKDIR /app

ENV TZ=Asia/Shanghai
ENV PYTHONPATH=/app
# 核心：将第一阶段准备好的虚拟环境直接考过来
ENV PATH="/app/.venv/bin:$PATH"

# 基础设置
COPY ./docker/gunicorn_conf.py ./docker/start.sh /
RUN chmod +x /start.sh

ENV APP_MODULE=_main:app
ENV MAX_WORKERS=1

# 拷贝依赖和代码
# 直接考 .venv 目录，避免了 pip install 的二次解析错误
COPY --from=builder /build/.venv /app/.venv
COPY --from=builder /tmp/bot.py /app/
COPY ./docker/_main.py /app/
COPY . /app/

# 这里的 pip 只装生产环境必须的 web server (这几个没 CUDA 麻烦，直接装)
RUN pip install --no-cache-dir gunicorn uvicorn[standard]

CMD ["/start.sh"]
