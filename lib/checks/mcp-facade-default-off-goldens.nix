# Frozen SHA-256 digests of builtins.toJSON over the projection in
# mcp-facade-default-off-projection.nix, freshly compared from base bd39621a
# and the candidate with the same locked inputs. The only changed input is
# homelab-contracts v5.19.2 at de3be0f0; nixpkgs is 752cbac9 and home-manager
# is 24f21905. The Home Manager assertions and projections were deepSeq'd for
# both systems before comparing. These values match the earlier 37b952fc
# baseline, now verified at the exact source base for this candidate.
# flakeLockSha256 and both projection digests track the all non-major dependencies
# update in #2855: its MCP server version bumps change store paths in the
# projection; byte counts are unchanged.
{
  baseCommit = "bd39621af5358bf01af73899f1761430ec6fae3d";
  flakeLockSha256 = "3cdabed773dd452f7927784b520a93920bdd4182ceaded432a75fe932c5f7fc1";
  projections = {
    aarch64-darwin = {
      bytes = 3357;
      sha256 = "bf2271b285799eb45cadf09294d95c3426c2bc928ab9f7c0330e68bcba725ae8";
    };
    x86_64-linux = {
      bytes = 3175;
      sha256 = "cb647d9304c2f3f985e2d0e49878e86c6dcd2c82f83086494a73952c5187718f";
    };
  };
}
