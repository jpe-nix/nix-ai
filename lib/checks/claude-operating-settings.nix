# Claude Code settings environment and auto-mode policy wiring.
{ pkgs, mkHmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  unsetConfig = mkHmConfig [ ];
  unsetEnv = unsetConfig.config.programs.claude.settings.env;
  autoModeEnvironment = unsetConfig.config.programs.claude.autoMode.environment;
  queryUrl = "https://metrics.example.invalid/api/query";
  tokenFile = "/tmp/test-agent-quota-token";
  setEnv =
    (mkHmConfig [
      {
        services.aiStack = {
          agentQuotaQueryUrl = queryUrl;
          agentQuotaTokenFile = tokenFile;
        };
      }
    ]).config.programs.claude.settings.env;
  sourceControlRules = builtins.filter (
    rule: pkgs.lib.hasInfix "Source control:" rule
  ) autoModeEnvironment;
  autoModeForcePushPolicyCorrect =
    builtins.length sourceControlRules == 1
    && pkgs.lib.hasSuffix "Force-push is off-limits on every branch." (builtins.head sourceControlRules)
    && !(pkgs.lib.hasInfix "Force-push to feature branches is routine; force-push to main is off-limits." (
      builtins.head sourceControlRules
    ));
in
{
  claude-operating-settings =
    assert
      !(unsetEnv ? AGENT_QUOTA_QUERY_URL) && !(unsetEnv ? AGENT_QUOTA_TOKEN_FILE)
      || throw "unset quota options must omit both quota environment variables from Claude settings";
    assert
      (setEnv.AGENT_QUOTA_QUERY_URL or null) == queryUrl
      && (setEnv.AGENT_QUOTA_TOKEN_FILE or null) == tokenFile
      || throw "configured quota options must render both values into Claude settings";
    assert
      autoModeForcePushPolicyCorrect
      || throw "auto-mode must describe force-push as off-limits on every branch";
    helpers.mkMarker "check-claude-operating-settings" "Claude operating settings: quota environment and auto-mode policy verified";
}
