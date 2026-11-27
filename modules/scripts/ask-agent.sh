#!/usr/bin/env bash
# ask-agent NAME REQUEST... — send one plain request to an agent and
# print its reply. The agent is the router model `agent-NAME`.
# A NAME ending in -clerk must answer with one clerk envelope (the prompt
# pack's schema). Any other reply prints an error envelope and exits 2, so a
# caller never acts on a malformed reply.
set -euo pipefail

usage="usage: ${0##*/} NAME REQUEST..."
name="${1:?$usage}"
shift
request="${*:?$usage}"

base="${ASK_AGENT_URL:-${LITELLM_LOCAL_URL:?ask-agent: set ASK_AGENT_URL or LITELLM_LOCAL_URL}}"
token="${ASK_AGENT_TOKEN:-${LITELLM_LOCAL_TOKEN:-local}}"
caller="${ASK_AGENT_CALLER:-unknown}"
timeout="${ASK_AGENT_TIMEOUT:-600}"

# The agent keys its session on the first user message, so a unique first line
# gives every call a fresh session. The line is a label for the agent's logs.
header="[caller: ${caller}; request: $(date +%s)-$$-${RANDOM}]"
body="$(jq -n --arg model "agent-${name}" --arg content "${header}
${request}" '{model: $model, messages: [{role: "user", content: $content}]}')"

out="$(mktemp)"
trap 'rm -f "$out" "$out.json"' EXIT
code="$(curl -sS -m "$timeout" -o "$out" -w '%{http_code}' \
  "${base%/}/v1/chat/completions" \
  -H "Authorization: Bearer ${token}" \
  -H 'Content-Type: application/json' \
  -d "$body")"

if [ "$code" != 200 ]; then
  detail="$(jq -r '.error.message // .detail // .' "$out" 2>/dev/null | head -c 400 || true)"
  echo "ask-agent: agent-${name} returned HTTP ${code}: ${detail}" >&2
  exit 1
fi
reply="$(jq -r '.choices[0].message.content' "$out")"
if [[ "$name" == *-clerk ]]; then
  printf '%s' "$reply" >"$out.json"
  schema="${ASK_AGENT_CLERK_SCHEMA:?ask-agent: set ASK_AGENT_CLERK_SCHEMA}"
  if ! check-jsonschema --schemafile "$schema" "$out.json" >/dev/null 2>&1; then
    echo "ask-agent: agent-${name} reply is not a clerk envelope: ${reply:0:400}" >&2
    jq -cn '{status: "error", outcome: "The agent reply was not a valid clerk envelope.",
      ids: [], items: [], readback: null,
      error: {code: "malformed_envelope", message: "The reply did not match the clerk envelope schema."}}'
    exit 2
  fi
fi
printf '%s\n' "$reply"
