#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACTS="${SCRIPT_DIR}/../../ml/artifacts/potia-qwen2.5-7b"
PORT="${PORT:-8001}"
MAX_LEN="${MAX_LEN:-4096}"
GPU_UTIL="${GPU_UTIL:-0.90}"

if [[ "${MODE:-merged}" == "lora" ]]; then
  exec vllm serve "${BASE_MODEL:-Qwen/Qwen2.5-7B-Instruct}" \
    --enable-lora \
    --lora-modules "potia=${ARTIFACTS}/adapter" \
    --max-lora-rank 16 \
    --port "${PORT}" --max-model-len "${MAX_LEN}" --gpu-memory-utilization "${GPU_UTIL}"
else
  exec vllm serve "${ARTIFACTS}/merged" \
    --served-model-name potia \
    --port "${PORT}" --max-model-len "${MAX_LEN}" --gpu-memory-utilization "${GPU_UTIL}"
fi
