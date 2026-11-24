# openwhispr — AI scopes and speech-to-text follow the local router.
#
# nix-ai is not a consumer of nix-openwhispr, so a stub declares the two
# options the module sets. Without the stub the module must set nothing.
{
  pkgs,
  mkHmConfig,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  stub =
    { lib, ... }:
    {
      options.programs.openwhispr = {
        inference = lib.mkOption {
          type = lib.types.attrsOf (lib.types.nullOr lib.types.attrs);
          default = { };
        };
        transcription = lib.mkOption {
          type = lib.types.nullOr lib.types.attrs;
          default = null;
        };
      };
    };
  router = {
    programs.litellmLocal.enable = true;
    services.aiStack = {
      llmEndpoint = "router";
      llmRouterEndpoint = "https://llm.example.invalid/v1";
      llmEndpointBearerFromEnv = true;
    };
  };
  cfg =
    (mkHmConfig [
      stub
      router
    ]).config;
  ow = cfg.programs.openwhispr;
  url = cfg.programs.litellmLocal.baseUrl;
  overridden =
    (mkHmConfig [
      stub
      router
      {
        programs.openwhispr.inference.noteFormatting = {
          url = "http://other.invalid/v1";
          model = "x";
        };
      }
    ]).config.programs.openwhispr.inference.noteFormatting;
in
{
  openwhispr-router =
    assert
      ow.inference.dictationCleanup == {
        inherit url;
        model = "fast";
      }
      || throw "openwhispr: cleanup must use the router's fast role";
    assert
      ow.inference.noteFormatting == {
        inherit url;
        model = "default";
      }
      || throw "openwhispr: note formatting must use the router's default role";
    assert
      ow.transcription == {
        inherit url;
        model = "qwen3-asr-1-7b";
      }
      || throw "openwhispr: transcription must use the router's speech-to-text model";
    assert overridden.model == "x" || throw "openwhispr: a host value must win over the default";
    assert
      !((mkHmConfig [ ]).options.programs ? openwhispr)
      || throw "openwhispr: without nix-openwhispr the module must declare nothing";
    helpers.mkMarker "check-openwhispr-router" "openwhispr: AI scopes and transcription follow the local router";
}
