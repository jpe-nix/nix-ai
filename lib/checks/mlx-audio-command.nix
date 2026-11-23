# mlx-audio command contract: mlx_audio.server has no --model flag, so the
# audio command passes only --port and --host.
{
  pkgs,
  hmConfigCatalog,
  mkHmConfig,
}:
let
  inherit (pkgs) lib;
  c = hmConfigCatalog.config.programs.mlx;
  audio = "mlx-community/Ming-3.0-tts-0.5B-8bit";
  commandBuilder = import ../../modules/mlx/model-server-cmd.nix {
    inherit (pkgs) lib;
    cfg = c // {
      modelBackends = c.modelBackends // {
        ${audio} = "mlx-audio";
      };
    };
    mlxModelServerPkg = pkgs.writeShellScriptBin "mlx-model-server" "";
    mlxModelServerPkgs = {
      mlx-audio = pkgs.writeShellScriptBin "stub-mlx-audio-server" "";
    };
  };
  command = commandBuilder.mkModelCmd audio;
  inklingHm = mkHmConfig [
    {
      programs.mlx = {
        enable = true;
        catalog.inkling-2-mini = {
          class = "resident";
          roles = [ "inkling-2-mini" ];
        };
      };
    }
  ];
  inklingCfg = inklingHm.config.programs.mlx;
  inkling = "mlx-community/Inkling-2-Mini-4bit";
  prVersions = import ../../lib/versions.nix;
  prServer = import ../../modules/mlx/mlx-lm-server.nix {
    inherit pkgs;
    cfg = inklingCfg;
    versions = prVersions;
  };
  inklingBuilder = import ../../modules/mlx/model-server-cmd.nix {
    inherit (pkgs) lib;
    cfg = inklingCfg;
    mlxModelServerPkg = pkgs.writeShellScriptBin "stub-mlx-model-server" "";
    mlxModelServerPkgs = {
      mlx-lm-pr = prServer.prPkg;
    };
  };
  inklingCommand = inklingBuilder.mkModelCmd inkling;
  inklingArgs = inklingBuilder.mkModelArgs inkling inklingCfg.port;
  inklingSnapshot = "${inklingCfg.huggingFaceHome}/hub/models--mlx-community--Inkling-2-Mini-4bit/snapshots/${
    inklingCfg.modelRevisions.${inkling}
  }";
  prServerFlags = [
    "--model"
    "--port"
    "--host"
    "--log-level"
    "--max-tokens"
    "--decode-concurrency"
    "--prompt-concurrency"
    "--prompt-cache-size"
    "--prompt-cache-bytes"
    "--prefill-step-size"
  ];
  inklingFlags = builtins.filter (arg: lib.hasPrefix "--" arg) inklingArgs;
in
{
  mlx-audio-command =
    assert
      builtins.match ".*stub-mlx-audio-server --port [0-9]+ --host [^ ]+" command != null
      && builtins.match ".*--model.*" command == null
      || throw "mlx-audio must compile without --model and with --port and --host: ${command}";
    pkgs.runCommand "check-mlx-audio-command" { } "touch $out";

  mlx-lm-pr-command =
    assert
      inklingCfg.modelBackends.${inkling} == "mlx-lm-pr"
      &&
        prVersions.mlxLmPrInstallSpec
        == "mlx-lm @ git+https://github.com/jundot/mlx-lm.git@e2b5bbd3bd9d186dea895e60802aa765e70b9d93"
      && lib.hasInfix "mlx-lm-pr-server" inklingCommand
      && builtins.elemAt inklingArgs 0 == "--model"
      && builtins.elemAt inklingArgs 1 == inklingSnapshot
      && lib.all (flag: lib.elem flag prServerFlags) inklingFlags
      || throw "Inkling must use the mlx-lm PR package, pass its exact HF snapshot path, and emit only flags accepted by the pinned PR server: ${inklingCommand}";
    pkgs.runCommand "check-mlx-lm-pr-command" {
      nativeBuildInputs = [ prServer.prPkg ];
    } "touch $out";
}
