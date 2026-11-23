# Join shared runtime metadata with the local MLX serving catalog.
{
  catalogEntry,
  mlxCatalogEntry ? null,
  roleModel ? { },
}:
let
  sourceServing = (roleModel.serving or { }) // ((catalogEntry.stage0 or { }).serving or { });
  backend = if mlxCatalogEntry == null then null else mlxCatalogEntry.backend or "mlx-lm";
  serving =
    if backend == null then
      sourceServing
    else
      sourceServing
      // {
        inherit backend;
        endpoint = sourceServing.endpoint or "/v1/chat/completions";
      };
  mlxChat =
    backend != null
    && builtins.elem backend [
      "mlx-lm"
      "mlx-lm-pr"
      "mlx-vlm"
      "mlx-vlm-native"
    ]
    && (serving.endpoint or null) == "/v1/chat/completions";
  # Speech residents serve the audio endpoints instead of chat completions.
  mlxAudio = backend == "mlx-audio";
in
{
  inherit serving mlxChat mlxAudio;
}
