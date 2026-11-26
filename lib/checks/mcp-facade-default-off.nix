# Check that the default-off native MCP configuration still evaluates, passes
# its Home Manager assertions, and enables no facade selector.
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
  inherit (pkgs.stdenv.hostPlatform) system;
  projectionsAndAssertionsPass = builtins.deepSeq hmConfigDefaultOff.config.assertions (
    builtins.deepSeq projection (
      builtins.all (assertion: assertion.assertion) hmConfigDefaultOff.config.assertions
    )
  );
in
{
  facade-canary-default-off-merge-base =
    assert
      projectionsAndAssertionsPass
      || throw "default-off Home Manager assertions failed or its MCP projection did not evaluate";
    assert
      !hmConfigDefaultOff.config.programs.aiMcp.facadeCanary
      && builtins.all (selected: !selected) (
        builtins.attrValues hmConfigDefaultOff.config.programs.aiMcp.facadeCanaryClients
      )
      || throw "default-off fixture enabled a facade selector";
    helpers.mkMarker "check-facade-canary-default-off-merge-base" "Default-off MCP maps evaluate, pass their assertions, and enable no facade selector on ${system}";
}
