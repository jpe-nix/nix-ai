# Guard the default-off native MCP configuration: the Home Manager assertions
# hold, the MCP projection evaluates, and no facade selector is enabled.
{
  pkgs,
  mkHmConfig,
  ...
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;
  gateway = "https://gateway.example.invalid";
  hmConfigDefaultOff = mkHmConfig [
    {
      programs.opencode.enable = true;
      programs.aiMcp.gatewayBaseUrl = gateway;
    }
  ];
  projection = import ./mcp-facade-default-off-projection.nix {
    inherit lib;
    codexMcpServers = hmConfigDefaultOff.config.programs.codex.generatedMcpServers;
    antigravityIdeMcpServers = hmConfigDefaultOff.config.programs.antigravity-ide.generatedMcpServers;
  } hmConfigDefaultOff;
  projectionsAndAssertionsPass = builtins.deepSeq hmConfigDefaultOff.config.assertions (
    builtins.deepSeq projection (
      builtins.all (assertion: assertion.assertion) hmConfigDefaultOff.config.assertions
    )
  );
in
{
  facade-canary-default-off =
    assert
      projectionsAndAssertionsPass
      || throw "default-off Home Manager assertions failed or its MCP projection does not evaluate";
    assert
      !hmConfigDefaultOff.config.programs.aiMcp.facadeCanary
      && builtins.all (selected: !selected) (
        builtins.attrValues hmConfigDefaultOff.config.programs.aiMcp.facadeCanaryClients
      )
      || throw "default-off fixture enabled a facade selector";
    helpers.mkMarker "check-facade-canary-default-off" "Default-off MCP projection evaluates, Home Manager assertions pass, and every facade selector stays off";
}
