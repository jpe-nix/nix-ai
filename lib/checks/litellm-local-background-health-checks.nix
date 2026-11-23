# litellm-local background health checks: absent by default, and set to a
# 300-second interval only when programs.litellmLocal.backgroundHealthChecks is
# on. The option runs for every route, so the default must stay off.
{
  pkgs,
  mkHmConfig,
}:
let
  general =
    enabled:
    (mkHmConfig [
      {
        programs.litellmLocal.backgroundHealthChecks = enabled;
      }
    ]).config.programs.litellmLocal.renderedConfig.general_settings;
  off = general false;
  on = general true;
in
{
  litellm-local-background-health-checks =
    assert
      !(off ? background_health_checks)
      || throw "litellm-local: background health checks must be absent unless backgroundHealthChecks is set";
    assert
      (on.background_health_checks == true && on.health_check_interval == 300)
      || throw "litellm-local: backgroundHealthChecks must set background_health_checks = true and health_check_interval = 300";
    pkgs.runCommand "check-litellm-local-background-health-checks" { } "touch $out";
}
