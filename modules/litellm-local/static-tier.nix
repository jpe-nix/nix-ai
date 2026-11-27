# Static resident routes and router fallbacks.
#
# Resident roles route locally unless `localModels` declares the same group.
# Every resident role that gets a route falls through to its own router rung
# (`<role>-homelab`) when the local deployment refuses or fails a request.
# Head aliases also send a request too large for the resident's window there.
#
# Each router rung is its own group (`<role>-homelab`) because a fallback
# target must be a named group; the `*` wildcard cannot be one.
#
# Each resident worker is one deployment (`<catalog key>-resident`) that admits
# as many requests as the worker decodes at once (the contract's `concurrency`).
# Its roles are priority routing groups over that deployment and their own
# router rung, so they share the worker's slots: when every slot is busy, a
# request moves to the router rung at once instead of queueing on the worker.
#
# A thinking-off sibling (`<role>-no-thinking`) of a role in `noThinkingRoles`
# routes to a sibling deployment with `extra_body` set per request. It uses the
# same worker and limits, and its own router rung carries the same body. Every
# other route keeps the worker's thinking default.
{
  lib,
  staticResidentModels,
  headAliases,
  localModels,
}:
let
  # Head aliases keep their overflow route. Empty when no resident is declared.
  headRoles = lib.optionals (staticResidentModels != { }) headAliases;
  routerRung = role: "${role}-homelab";
  localModelDefinesRole = role: builtins.any (model: model.name == role) localModels;
  # Roles that get a resident route on this host. A role a localModels rung
  # already names is served by that rung, so it has no static route.
  routedRoles = lib.unique (
    lib.concatMap (
      modelId:
      builtins.filter (role: !(localModelDefinesRole role)) (
        builtins.attrNames staticResidentModels.${modelId}.roles
      )
    ) (builtins.attrNames staticResidentModels)
  );
  # Every routed role gets a router rung and a fallback to it.
  fallbackRoles = lib.unique (headRoles ++ routedRoles);

  # Roles that also get a thinking-off sibling. Only a role this host routes.
  noThinkingRoles = builtins.filter (role: builtins.elem role routedRoles) [ "small" ];
  noThinkingName = role: "${role}-no-thinking";
  # LiteLLM merges a deployment's `extra_body` into the request JSON. The MLX
  # chat template reads `chat_template_kwargs` per request, which overrides the
  # worker's `--chat-template-args` default (enable_thinking = true).
  noThinkingBody = {
    chat_template_kwargs = {
      enable_thinking = false;
    };
  };

  # One deployment per resident worker. Every role on that worker is a routing
  # group that points at it, so the deployment's max_parallel_requests counts
  # the worker's in-flight requests across all of its roles.
  residentName = modelId: "${staticResidentModels.${modelId}.catalogKey}-resident";
  routedRolesOf =
    modelId:
    builtins.filter (role: !(localModelDefinesRole role)) (
      builtins.attrNames staticResidentModels.${modelId}.roles
    );
  routedResidents = builtins.filter (modelId: routedRolesOf modelId != [ ]) (
    builtins.attrNames staticResidentModels
  );
  noThinkingRolesOf =
    modelId: builtins.filter (role: builtins.elem role noThinkingRoles) (routedRolesOf modelId);

  residentRoute =
    modelId:
    let
      contract = staticResidentModels.${modelId};
    in
    {
      model_name = residentName modelId;
      litellm_params = {
        # custom_openai with chat completions, as the fallback tier's local rung: the openai
        # provider sends /v1/messages through LiteLLM's Responses bridge, and mlx-lm-server
        # implements chat completions only, so Anthropic-shaped callers got a 404.
        model = "custom_openai/${modelId}";
        use_chat_completions_api = true;
        api_base = "http://127.0.0.1:${toString contract.servicePort}/v1";
        api_key = "os.environ/OPENAI_API_KEY";
        timeout = contract.timeoutSeconds;
        stream_timeout = contract.timeoutSeconds;
        max_parallel_requests = contract.concurrency;
      };
      model_info = {
        max_input_tokens = contract.maxInputTokens;
        max_output_tokens = contract.maxOutputTokens;
      }
      // lib.optionalAttrs (contract.mode != null) { inherit (contract) mode; };
    };
  # The thinking-off sibling needs its own deployment for `extra_body`, so it
  # keeps its own in-flight count.
  noThinkingRoute =
    modelId:
    let
      route = residentRoute modelId;
    in
    route
    // {
      model_name = noThinkingName route.model_name;
      litellm_params = route.litellm_params // {
        extra_body = noThinkingBody;
      };
    };

  # A priority group tries the resident first. When the resident is already at
  # max_parallel_requests, LiteLLM refuses it with a 429 at once and the group
  # moves to the role's router rung in the same request.
  # LiteLLM reserves some group names ("default" is its implicit group). Such a
  # role gets a suffixed group, and a model_group_alias keeps its own name callable.
  reservedGroupNames = [ "default" ];
  groupName = role: if builtins.elem role reservedGroupNames then "${role}-role" else role;
  priorityGroup = role: deployment: {
    group_name = groupName role;
    models = [
      deployment
      (routerRung role)
    ];
    routing_strategy = "priority";
    model_priorities = {
      ${deployment} = 1;
      ${routerRung role} = 2;
    };
  };
in
{
  routes =
    map residentRoute routedResidents
    ++ map noThinkingRoute (
      builtins.filter (modelId: noThinkingRolesOf modelId != [ ]) routedResidents
    );

  modelGroupAlias = lib.listToAttrs (
    map (role: lib.nameValuePair role (groupName role)) (
      builtins.filter (role: groupName role != role) (
        lib.concatMap (
          modelId: routedRolesOf modelId ++ map noThinkingName (noThinkingRolesOf modelId)
        ) routedResidents
      )
    )
  );

  routingGroups = lib.concatMap (
    modelId:
    map (role: priorityGroup role (residentName modelId)) (routedRolesOf modelId)
    ++ map (role: priorityGroup (noThinkingName role) (noThinkingName (residentName modelId))) (
      noThinkingRolesOf modelId
    )
  ) routedResidents;

  routerRungs =
    map (role: {
      model_name = routerRung role;
      litellm_params = {
        model = "openai/${role}";
        api_base = "os.environ/LLM_ROUTER_URL";
        api_key = "os.environ/OPENAI_API_KEY";
      };
    }) fallbackRoles
    ++ map (role: {
      model_name = routerRung (noThinkingName role);
      litellm_params = {
        model = "openai/${role}";
        api_base = "os.environ/LLM_ROUTER_URL";
        api_key = "os.environ/OPENAI_API_KEY";
        extra_body = noThinkingBody;
      };
    }) noThinkingRoles;

  fallbacks =
    map (role: {
      ${role} = [ (routerRung role) ];
    }) fallbackRoles
    ++ map (role: {
      ${noThinkingName role} = [ (routerRung (noThinkingName role)) ];
    }) noThinkingRoles;

  contextWindowFallbacks =
    map (role: { ${role} = [ (routerRung role) ]; }) headRoles
    ++ map (role: { ${noThinkingName role} = [ (routerRung (noThinkingName role)) ]; }) (
      builtins.filter (role: builtins.elem role headRoles) noThinkingRoles
    );
}
