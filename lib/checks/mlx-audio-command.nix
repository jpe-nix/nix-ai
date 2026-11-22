# mlx-audio command contract: mlx_audio.server has no --model flag, so the
# audio command passes only --port and --host.
{
  pkgs,
  hmConfigCatalog,
}:
let
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
in
{
  mlx-audio-command =
    assert
      builtins.match ".*stub-mlx-audio-server --port [0-9]+ --host [^ ]+" command != null
      && builtins.match ".*--model.*" command == null
      || throw "mlx-audio must compile without --model and with --port and --host: ${command}";
    pkgs.runCommand "check-mlx-audio-command" { } "touch $out";
}
