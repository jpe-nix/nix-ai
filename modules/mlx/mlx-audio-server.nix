# mlx-audio speech and transcription serving path, mirroring ./mlx-vlm-server.nix.
# mlx_audio.server has no --model flag, so callers pass only --host and --port.
{
  pkgs,
  mlxAudioInstallSpec,
  uvPythonVersion,
}:
let
  name = "mlx-audio-server";
in
{
  pkg = pkgs.writeShellScriptBin name ''
    exec ${pkgs.uv}/bin/uvx --python ${uvPythonVersion} --from "${mlxAudioInstallSpec}" python -m mlx_audio.server "$@"
  '';

  launchScriptBasename = name;
}
