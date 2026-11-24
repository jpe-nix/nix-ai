# Static resident mode: every resident role falls through to its own router rung
# (`<role>-homelab`), which forwards the role name to the router. The `small`
# head alias also sends a request too large for its window to that rung.
{
  pkgs,
  hmConfigStaticServing,
}:
let
  inherit (pkgs) lib;
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (hmConfigStaticServing.config.programs.litellmLocal) renderedConfig;
  routeFor = helpers.routeFor renderedConfig;
  rungFor = name: lib.findFirst (route: route.model_name == name) null renderedConfig.model_list;
  fallbackFor =
    group: lib.findFirst (entry: entry ? ${group}) null renderedConfig.litellm_settings.fallbacks;
  windowFallbackFor =
    group:
    lib.findFirst (
      entry: entry ? ${group}
    ) null renderedConfig.litellm_settings.context_window_fallbacks;
  small = routeFor "small";
  smallRouter = routeFor "small-homelab";
  smallNoThinking = routeFor "small-no-thinking";
  smallNoThinkingRung = rungFor "small-no-thinking-homelab";
  noThinkingBody = {
    chat_template_kwargs = {
      enable_thinking = false;
    };
  };
  contracts = hmConfigStaticServing.config.programs.mlx.staticResidentContracts;
  small9b = contracts."mlx-community/Qwen3.5-9B-OptiQ-4bit";
  residentRoles = lib.unique (
    lib.concatMap (contract: builtins.attrNames contract.roles) (builtins.attrValues contracts)
  );
  roleHasRouterFallback =
    role:
    let
      entry = fallbackFor role;
      rung = rungFor "${role}-homelab";
    in
    entry != null
    && entry.${role} == [ "${role}-homelab" ]
    && rung != null
    && rung.litellm_params.model == "openai/${role}"
    && rung.litellm_params.api_base == "os.environ/LLM_ROUTER_URL";
  rolesWithoutRouterFallback = builtins.filter (role: !(roleHasRouterFallback role)) residentRoles;
in
{
  mlx-static-resident-router-fallback =
    if
      small.litellm_params.model == "openai/${small9b.model}"
      && small.litellm_params.api_base == "http://127.0.0.1:${toString small9b.servicePort}/v1"
      && (fallbackFor "small").small == [ "small-homelab" ]
      && (windowFallbackFor "small").small == [ "small-homelab" ]
      && smallRouter.litellm_params.model == "openai/small"
      && smallRouter.litellm_params.api_base == "os.environ/LLM_ROUTER_URL"
    then
      helpers.mkMarker "check-mlx-static-resident-router-fallback" "a stopped `small` resident falls back to the router under the same name, and an overflowing request goes there too"
    else
      throw "the `small` head alias must fall back to a router rung named small-homelab that forwards `small`, and overflow must reach it";

  mlx-static-role-router-fallbacks =
    if residentRoles != [ ] && rolesWithoutRouterFallback == [ ] then
      helpers.mkMarker "check-mlx-static-role-router-fallbacks" "every static resident role falls back to its own <role>-homelab router rung, which forwards the role name to the router"
    else
      throw "every static resident role must fall back to its <role>-homelab router rung; missing: ${builtins.toJSON rolesWithoutRouterFallback}";

  mlx-static-no-thinking-alias =
    if
      smallNoThinking.litellm_params.model == small.litellm_params.model
      && smallNoThinking.litellm_params.api_base == small.litellm_params.api_base
      && smallNoThinking.litellm_params.extra_body == noThinkingBody
      && smallNoThinking.model_info == small.model_info
      && !(small.litellm_params ? extra_body)
      && (fallbackFor "small-no-thinking")."small-no-thinking" == [ "small-no-thinking-homelab" ]
      && (windowFallbackFor "small-no-thinking")."small-no-thinking" == [ "small-no-thinking-homelab" ]
      && smallNoThinkingRung != null
      && smallNoThinkingRung.litellm_params.model == "openai/small"
      && smallNoThinkingRung.litellm_params.api_base == "os.environ/LLM_ROUTER_URL"
      && smallNoThinkingRung.litellm_params.extra_body == noThinkingBody
    then
      helpers.mkMarker "check-mlx-static-no-thinking-alias" "small-no-thinking shares the small resident's deployment and sends thinking-off per request; its overflow and router fallback forward small with the same body, and small keeps the worker default"
    else
      throw "small-no-thinking must mirror the small route with extra_body enable_thinking = false, fall back to small-no-thinking-homelab, which forwards small with the same body; small must carry no extra_body";

  # Every role on one worker shares that worker's one deployment, so its slot
  # count covers all of them, and each role tries the worker before its rung.
  mlx-static-shared-resident-slots =
    let
      sharedSlotsOf =
        config:
        let
          groups = config.router_settings.routing_groups or [ ];
          aliases = config.router_settings.model_group_alias or { };
          groupFor = role: lib.findFirst (g: g.group_name == (aliases.${role} or role)) null groups;
          # null when the role has no group, so a missing group fails the check, not the evaluation.
          residentOf =
            role:
            let
              group = groupFor role;
            in
            if group == null || group.models == [ ] then null else builtins.head group.models;
          resident = residentOf "small";
          smallRoute = helpers.routeFor config "small";
          sharesWorker =
            role:
            let
              group = groupFor role;
            in
            group != null
            && group.routing_strategy == "priority"
            &&
              group.models == [
                resident
                "${role}-homelab"
              ]
            && group.model_priorities.${resident} < group.model_priorities."${role}-homelab";
          smallWorkerRoles = builtins.attrNames small9b.roles;
          notShared = builtins.filter (role: !(sharesWorker role)) smallWorkerRoles;
        in
        {
          inherit notShared;
          ok =
            smallWorkerRoles != [ ]
            && notShared == [ ]
            # LiteLLM refuses to start with a group named after its reserved "default" group.
            && !(builtins.any (g: g.group_name == "default") groups)
            && smallRoute != null
            && smallRoute.litellm_params.max_parallel_requests == small9b.concurrency
            && builtins.length (builtins.filter (r: r.model_name == resident) config.model_list) == 1;
        };
      live = sharedSlotsOf renderedConfig;
      withSettings =
        settings: renderedConfig // { router_settings = renderedConfig.router_settings // settings; };
      # Negative cases: the check must reject a config with no routing groups,
      # and one that names a group after LiteLLM's reserved "default" group.
      noGroups = sharedSlotsOf (withSettings {
        routing_groups = [ ];
        model_group_alias = { };
      });
      reservedName = sharedSlotsOf (withSettings {
        routing_groups = map (
          g: if g.group_name == "default-role" then g // { group_name = "default"; } else g
        ) (renderedConfig.router_settings.routing_groups or [ ]);
      });
    in
    if live.ok && !noGroups.ok && !reservedName.ok then
      helpers.mkMarker "check-mlx-static-shared-resident-slots" "every role on the small worker is a priority group over one shared deployment, then its own router rung; configs without groups or with a reserved group name are rejected"
    else
      throw "every role on a resident worker must be a priority routing group over that worker's single deployment, then <role>-homelab; not shared: ${builtins.toJSON live.notShared}; negative cases rejected: no groups ${
        lib.boolToString (!noGroups.ok)
      }, reserved name ${lib.boolToString (!reservedName.ok)}";
}
