# Always-resident entries for the shared-residents layer. Limits come from
# homelab-contracts. Throughput, queue and output values are PROVISIONAL: each
# names the measured row it was copied from, and each is replaced by a value
# measured after activation. Slower stated values only lengthen timeouts.
{ modelCatalog }:
let
  inkling = modelCatalog."mlx-community/Inkling-2-Mini-4bit".profiles.mlx;
  gemma = modelCatalog."mlx-community/gemma-4-12B-it-4bit".profiles.mlx;
  asr = modelCatalog."mlx-community/Qwen3-ASR-1.7B-8bit".profiles.mlx;
  tts = modelCatalog."mlx-community/Ming-3.0-tts-0.5B-8bit".profiles.mlx;
in
{
  # mlx-vlm native server. The per-stream KV window is capped with
  # --max-kv-size through maxKvTokens. Prefill and decode are copied from the
  # measured Qwen3.8-27B row, a dense model slower than this 3.4B-active MoE.
  inkling-2-mini = {
    model = "mlx-community/Inkling-2-Mini-4bit";
    revision = "9c0e2960609ba7cb40daf92c6f7bf8ed56e1dd62";
    backend = "mlx-vlm-native";
    weightGb = 17.31;
    contextWindowTokens = inkling.context_window;
    maxOutputTokens = 8192;
    concurrency = inkling.max_parallel_requests;
    queueSize = 25;
    prefillTokensPerSecond = 150;
    decodeTokensPerSecond = 17;
    maxKvTokens = 65536;
    servicePort = 11428;
    args = [ ];
    classes.resident = { };
  };

  # mlx-lm server (Gemma 4 text path; mlx-lm 0.32.2 maps gemma4_unified to
  # gemma4). Prefill and decode are the measured Qwen3.5-9B row scaled by 9/12,
  # so the 12B model is assumed to run 12/9 slower. The prompt cache is pinned
  # to a 2.5 GB budget.
  gemma-4-12b = {
    model = "mlx-community/gemma-4-12B-it-4bit";
    revision = "73bcf09092aa277861d5a191b989b666f7f32e8f";
    weightGb = 6.74;
    kv = {
      kvLayers = 8;
      kvHeads = 1;
      headDim = 512;
      kvDtypeBytes = 2;
    };
    contextWindowTokens = gemma.context_window;
    maxOutputTokens = 4096;
    concurrency = gemma.max_parallel_requests;
    queueSize = 25;
    prefillTokensPerSecond = 450;
    decodeTokensPerSecond = 30;
    servicePort = 11429;
    args = [ ];
    classes.resident.cacheProvisioning.pinned = {
      mb = 2560;
      reason = "provisional prompt-cache budget; replaced by a measured value after activation";
      tracking = "shared-residents: measure after activation";
    };
  };

  # mlx-audio transcription server. It loads the repo id a request names and
  # has no --model flag, so no revision can be pinned. Audio has no measured
  # throughput row, so the request timeout is a fixed provisional value.
  qwen3-asr-1-7b = {
    model = "mlx-community/Qwen3-ASR-1.7B-8bit";
    backend = "mlx-audio";
    weightGb = 2.46;
    contextWindowTokens = asr.context_window;
    maxOutputTokens = 4096;
    concurrency = asr.max_parallel_requests;
    queueSize = 25;
    fixedTimeoutSeconds = 300;
    mode = "audio_transcription";
    servicePort = 11430;
    args = [ ];
    classes.resident = { };
  };

  # mlx-audio speech server. Same fixed provisional timeout as the ASR entry.
  ming-3-0-tts = {
    model = "mlx-community/Ming-3.0-tts-0.5B-8bit";
    backend = "mlx-audio";
    weightGb = 1.6;
    contextWindowTokens = tts.context_window;
    maxOutputTokens = 4096;
    concurrency = tts.max_parallel_requests;
    queueSize = 25;
    fixedTimeoutSeconds = 300;
    mode = "audio_speech";
    servicePort = 11431;
    args = [ ];
    classes.resident = { };
  };
}
