# Local LiteLLM Proxy — health-check option declarations.
{ lib, ... }:
{
  options.programs.litellmLocal.backgroundHealthChecks = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Run LiteLLM background health checks on every route, each
      health_check_interval seconds (300). A check sends a real request
      upstream: an audio route sends a short transcription or speech request
      on every interval. Off by default.
    '';
  };
}
