# Shared residents: four always-resident servers evaluate under the resident
# cap, their serve commands carry the caps the catalog declares, and their
# LiteLLM alias routes carry the audio mode.
{
  pkgs,
  mkHmConfig,
}:
let
  inherit (pkgs) lib;
  hm = mkHmConfig [
    {
      programs.mlx = {
        enable = true;
        catalog = {
          inkling-2-mini = {
            class = "resident";
            roles = [ "inkling-2-mini" ];
          };
          gemma-4-12b = {
            class = "resident";
            roles = [ "gemma-4-12b" ];
          };
          qwen3-asr-1-7b = {
            class = "resident";
            roles = [ "qwen3-asr-1.7b" ];
          };
          ming-3-0-tts = {
            class = "resident";
            roles = [ "ming-3.0-tts" ];
          };
        };
      };
      programs.litellmLocal.enable = true;
      services.aiStack = {
        llmEndpoint = "router";
        llmRouterEndpoint = "https://router.example.invalid/v1";
        llmEndpointTokenFile = "/tmp/test-router-token";
      };
    }
  ];
  cfg = hm.config.programs.mlx;
  contracts = cfg.staticResidentContracts;
  commands = import ../../modules/mlx/model-server-cmd.nix {
    inherit lib cfg;
    mlxModelServerPkg = pkgs.writeShellScriptBin "mlx-model-server" "";
    mlxModelServerPkgs = {
      mlx-audio = pkgs.writeShellScriptBin "stub-mlx-audio-server" "";
    };
  };
  inkling = "mlx-community/Inkling-2-Mini-4bit";
  gemma = "mlx-community/gemma-4-12B-it-4bit";
  asr = "mlx-community/Qwen3-ASR-1.7B-8bit";
  tts = "mlx-community/Ming-3.0-tts-0.5B-8bit";
  models = [
    inkling
    gemma
    asr
    tts
  ];
  routes = hm.config.programs.litellmLocal.renderedConfig.model_list;
  routeFor = name: lib.findFirst (route: route.model_name == name) null routes;
  allAssertionsHold = lib.all (a: a.assertion) hm.config.assertions;
in
{
  mlx-shared-residents =
    assert
      allAssertionsHold
      || throw "mlx shared residents: a module assertion failed under the four-resident cap";
    assert
      builtins.length (builtins.attrNames contracts) == 4
      || throw "mlx shared residents: expected four static resident contracts";
    assert
      lib.all (m: contracts ? ${m}) models
      || throw "mlx shared residents: a shared resident has no static contract";
    assert
      builtins.match ".*--max-kv-size 65536.*" (commands.mkModelCmd inkling) != null
      || throw "mlx shared residents: Inkling must cap its KV window at 65536 tokens";
    assert
      builtins.match ".*--prompt-cache-bytes 2684354560.*" (commands.mkModelCmd gemma) != null
      || throw "mlx shared residents: Gemma must pin its prompt cache at 2560 MB";
    assert
      builtins.match ".*--model.*" (commands.mkModelCmd asr) == null
      && builtins.match ".*--model.*" (commands.mkModelCmd tts) == null
      || throw "mlx shared residents: mlx-audio commands must not pass --model";
    assert
      contracts.${asr}.timeoutSeconds == 300 && contracts.${asr}.pipeTimeoutSeconds == 600
      || throw "mlx shared residents: ASR must use the fixed 300 s request and 600 s pipe timeouts";
    assert
      contracts.${tts}.timeoutSeconds == 300 && contracts.${tts}.pipeTimeoutSeconds == 600
      || throw "mlx shared residents: TTS must use the fixed 300 s request and 600 s pipe timeouts";
    assert
      (routeFor "qwen3-asr-1.7b").model_info.mode == "audio_transcription"
      || throw "mlx shared residents: the ASR alias route must carry mode audio_transcription";
    assert
      (routeFor "ming-3.0-tts").model_info.mode == "audio_speech"
      || throw "mlx shared residents: the TTS alias route must carry mode audio_speech";
    pkgs.runCommand "check-mlx-shared-residents" { } "touch $out";
}
