# Catalog-derived serving, routing, queue and timeout limits for static
# resident model servers (programs.mlx.staticResidentContracts).
{
  lib,
  config,
  cfg,
  enabled,
  entryFor,
  capContext,
  servedConcurrency,
}:
let
  derive = import ./derive.nix { inherit lib; };
in
lib.mapAttrs' (
  name: _sel:
  let
    entry = entryFor name;
    timeouts =
      if entry ? fixedTimeoutSeconds then
        {
          requestTimeoutSeconds = entry.fixedTimeoutSeconds;
          pipeTimeoutSeconds = 2 * entry.fixedTimeoutSeconds;
        }
      else
        derive.requestTimeouts {
          contextWindowTokens = capContext entry.contextWindowTokens;
          inherit (entry)
            maxOutputTokens
            queueSize
            prefillTokensPerSecond
            decodeTokensPerSecond
            ;
          concurrency = servedConcurrency entry;
        };
    roles = lib.filterAttrs (_: model: model == entry.model) config.services.aiStack.models;
  in
  lib.nameValuePair entry.model {
    inherit (entry)
      model
      servicePort
      maxOutputTokens
      queueSize
      weightGb
      ;
    contextWindowTokens = capContext entry.contextWindowTokens;
    concurrency = servedConcurrency entry;
    catalogKey = name;
    launchdLabel = if roles ? default then "dev.mlx-model-server" else "dev.mlx-model-server.${name}";
    backend = cfg.modelBackends.${entry.model} or cfg.modelServerBackend;
    maxInputTokens = capContext entry.contextWindowTokens - entry.maxOutputTokens;
    timeoutSeconds = timeouts.requestTimeoutSeconds;
    inherit (timeouts) pipeTimeoutSeconds;
    inherit roles;
    mode = entry.mode or null;
  }
) (lib.filterAttrs (name: sel: sel.class == "resident" && (entryFor name) ? servicePort) enabled)
