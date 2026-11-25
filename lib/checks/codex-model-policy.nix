# Codex OpenAI model policy: Luna at xhigh (AGENTS.md, "Delegation routing").
{
  pkgs,
  hmConfig,
}:
let
  cfg = hmConfig.config.programs.codex;
  homeFileNames = builtins.attrNames hmConfig.config.home.file;
  codexProfilePaths = builtins.filter (
    path: pkgs.lib.hasInfix "codex/" path && pkgs.lib.hasSuffix ".config.toml" path
  ) homeFileNames;
  codexProfileSources = map (
    path: (builtins.getAttr path hmConfig.config.home.file).source
  ) codexProfilePaths;
  # The policy's primary target is config.toml itself, and the activation merge
  # deploys it rather than home.file, so recover its store path from the
  # activation script the same way codex-credential-store does.
  configTomlActivation = hmConfig.config.home.activation.codexConfigMerge.data;
in
{
  # Apply the OpenAI model policy to OpenAI profiles; Z.ai and LiteLLM profiles keep their provider settings.
  codex-openai-model-policy =
    assert cfg.modelFamily == "luna";
    assert cfg.model == null || pkgs.lib.hasSuffix "-luna" cfg.model;
    assert cfg.modelReasoningEffort == "xhigh";
    assert cfg.planModeReasoningEffort == "xhigh";
    pkgs.runCommand "check-codex-openai-model-policy"
      {
        nativeBuildInputs = [
          pkgs.gnugrep
          pkgs.python3
        ];
        activation = configTomlActivation;
        passAsFile = [ "activation" ];
      }
      ''
        configToml=$(grep -m1 -oE '/nix/store/[^"[:space:]]*codex-config\.toml' "$activationPath")
        if [ -z "$configToml" ]; then
          echo "FAIL: the codex activation script references no codex-config.toml" >&2
          exit 1
        fi
        python3 - "$configToml" ${pkgs.lib.escapeShellArgs (map toString codexProfileSources)} <<'PYEOF'
        import sys
        import tomllib

        checked = 0
        for profile_path in sys.argv[1:]:
            with open(profile_path, "rb") as profile_file:
                profile = tomllib.load(profile_file)

            provider = profile.get("model_provider", "openai")
            if provider is not None and provider.lower() != "openai":
                continue

            # model is rendered only when programs.codex.model is set; otherwise
            # the Luna slug resolves at activation from Codex's own model cache.
            model = profile.get("model")
            if model is not None:
                assert model.endswith("-luna"), profile_path
            assert profile.get("model_reasoning_effort") == "xhigh", profile_path
            checked += 1

        assert checked > 0, (
            "no OpenAI-provider Codex config or profile was checked; "
            "the scan never reached config.toml and every profile was skipped"
        )

        print(f"codex-openai-model-policy: {checked} OpenAI configs/profiles use Luna at xhigh")
        PYEOF
        touch $out
      '';
}
