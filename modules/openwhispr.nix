# Points OpenWhispr's AI scopes and speech-to-text at the local router.
#
# Applies only when the nix-openwhispr Home Manager module is imported and the
# local router is enabled. The URL comes from programs.litellmLocal.baseUrl and
# the models are router role names, so a role or port change reaches OpenWhispr
# with no edit here. Every value is a default a host can override.
{
  config,
  lib,
  options,
  ...
}:
let
  router = config.programs.litellmLocal;
  endpoint =
    model:
    lib.mkDefault {
      url = router.baseUrl;
      inherit model;
    };
in
{
  config = lib.optionalAttrs (options.programs ? openwhispr) (
    lib.mkIf router.enable {
      programs.openwhispr = {
        inference = {
          dictationCleanup = endpoint "fast";
          dictationTranslation = endpoint "fast";
          noteFormatting = endpoint "default";
          dictationAgent = endpoint "default";
          chatIntelligence = endpoint "default";
        };
        # The router serves speech-to-text under its catalog name; no role maps to it.
        transcription = endpoint "qwen3-asr-1-7b";
      };
    }
  );
}
