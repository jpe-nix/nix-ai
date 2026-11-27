# Behavioural and routing checks for the packaged ask-agent command.
{
  pkgs,
  src,
  hmConfig,
  hmConfigLitellmLocal,
}:
let
  inherit (pkgs) lib;
  enabled = hmConfigLitellmLocal.config;
  askAgent = lib.findFirst (package: (package.name or "") == "ask-agent") null enabled.home.packages;
  routedConfig = enabled.programs.litellmLocal.renderedConfig;
  localConfig = hmConfig.config.programs.litellmLocal.renderedConfig;
  agentRoute = lib.findFirst (
    deployment: deployment.model_name == "agent-*"
  ) null routedConfig.model_list;
  hasAgentRoute =
    rendered: lib.any (deployment: deployment.model_name == "agent-*") rendered.model_list;
  fallbackMappings =
    (routedConfig.litellm_settings.fallbacks or [ ])
    ++ (routedConfig.router_settings.context_window_fallbacks or [ ]);
  fallbackNames = lib.concatMap (
    mapping: (builtins.attrNames mapping) ++ lib.concatLists (builtins.attrValues mapping)
  ) fallbackMappings;
  routeIsCorrect =
    agentRoute != null
    &&
      agentRoute.litellm_params == {
        model = "openai/agent-*";
        api_base = "os.environ/LLM_ROUTER_URL";
        api_key = "os.environ/OPENAI_API_KEY";
        num_retries = 0;
        timeout = 1800;
      }
    && !(agentRoute ? fallbacks)
    && !(lib.elem "agent-*" fallbackNames);
in
assert askAgent != null || throw "litellm-local must install the ask-agent package when enabled";
assert
  routeIsCorrect
  || throw "the agent wildcard must forward to the shared router with no retries or fallbacks";
assert
  hasAgentRoute routedConfig
  || throw "the agent wildcard must render when the shared router is configured";
assert
  !(hasAgentRoute localConfig) || throw "the agent wildcard must be absent without the shared router";
{
  # Expose the command derivation as a buildable check output as well as
  # building it through the behavioural test below.
  ask-agent-package = askAgent;

  ask-agent-command =
    pkgs.runCommand "check-ask-agent-command"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.curl
          pkgs.gnugrep
          pkgs.jq
          pkgs.python3
          pkgs.shellcheck
        ];
      }
      ''
            set -euo pipefail
            shellcheck ${src}/modules/scripts/ask-agent.sh

            work="$(mktemp -d)"
            stub_pid=""
            cleanup() {
              if [ -n "$stub_pid" ]; then
                kill "$stub_pid" 2>/dev/null || true
              fi
              rm -rf "$work"
            }
            trap cleanup EXIT

            cat > "$work/stub.py" <<'PY'
        import http.server, json, pathlib, re, socket, socketserver, sys

        work = pathlib.Path(sys.argv[1])
        envelope = json.dumps({
            "status": "ok", "outcome": "Found one task.", "ids": ["12"],
            "items": [{"id": 12, "title": "Sample"}], "readback": None, "error": None,
        })
        replies = {"hello world": "mock reply", "envelope": envelope, "prose": "Done."}
        loopback = socket.inet_ntoa(socket.INADDR_LOOPBACK.to_bytes(4, "big"))

        class Server(http.server.HTTPServer):
            def server_bind(self):
                socketserver.TCPServer.server_bind(self)
                self.server_name, self.server_port = self.server_address[:2]

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                raw = self.rfile.read(int(self.headers["content-length"]))
                request = json.loads(raw)
                with (work / "requests.jsonl").open("a") as log:
                    log.write(json.dumps(request) + "\n")
                content = request["messages"][0]["content"].splitlines()
                if self.path != "/v1/chat/completions":
                    status = 400
                    payload = {"error": {"message": "unexpected request path"}}
                elif (
                    request["model"] not in ("agent-demo", "agent-demo-clerk")
                    or len(content) != 2
                    or re.fullmatch(
                        r"\[caller: [^;]+; request: [0-9]+-[0-9]+-[0-9]+\]",
                        content[0],
                    ) is None
                    or content[1] not in (*replies, "rate-limit")
                ):
                    status = 400
                    payload = {"error": {"message": "unexpected request body"}}
                elif content[-1] == "rate-limit":
                    status = 429
                    payload = {"error": {"message": "rate limited"}}
                else:
                    status = 200
                    payload = {"choices": [{"message": {"content": replies[content[1]]}}]}
                body = json.dumps(payload).encode()
                self.send_response(status)
                self.send_header("content-type", "application/json")
                self.send_header("content-length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        server = Server((loopback, 0), Handler)
        (work / "address").write_text(loopback)
        (work / "port").write_text(str(server.server_port))
        server.serve_forever()
        PY

            python3 "$work/stub.py" "$work" >"$work/stub.log" 2>&1 &
            stub_pid=$!
            for _ in $(seq 1 50); do
              [ -s "$work/port" ] && break
              sleep 0.1
            done
            [ -s "$work/port" ] || {
              echo "mock server did not bind a port" >&2
              cat "$work/stub.log" >&2
              exit 1
            }

            base="http://$(cat "$work/address"):$(cat "$work/port")"
            output="$(ASK_AGENT_URL="$base" ASK_AGENT_CALLER="test" ${askAgent}/bin/ask-agent demo hello world)"
            [ "$output" = "mock reply" ] || {
              echo "ask-agent returned '$output', expected 'mock reply'" >&2
              exit 1
            }

            if ASK_AGENT_URL="$base" ${askAgent}/bin/ask-agent demo rate-limit >"$work/429.out" 2>"$work/429.err"; then
              echo "ask-agent unexpectedly accepted a 429 response" >&2
              exit 1
            fi
            grep -qF "HTTP 429" "$work/429.err" || {
              echo "ask-agent stderr did not report HTTP 429" >&2
              cat "$work/429.err" >&2
              exit 1
            }

            # A clerk's reply must be one clerk envelope; prose is replaced by an error envelope.
            envelope="$(ASK_AGENT_URL="$base" ${askAgent}/bin/ask-agent demo-clerk envelope)"
            [ "$(jq -r '.status + " " + .ids[0]' <<<"$envelope")" = "ok 12" ] || {
              echo "ask-agent changed a valid clerk envelope: $envelope" >&2
              exit 1
            }

            status=0
            ASK_AGENT_URL="$base" ${askAgent}/bin/ask-agent demo-clerk prose >"$work/prose.out" 2>"$work/prose.err" || status=$?
            [ "$status" = 2 ] || {
              echo "ask-agent exited $status for a malformed clerk reply, expected 2" >&2
              cat "$work/prose.err" >&2
              exit 1
            }
            [ "$(jq -r '.status + " " + .error.code' "$work/prose.out")" = "error malformed_envelope" ] || {
              echo "ask-agent did not print the malformed_envelope error envelope" >&2
              cat "$work/prose.out" >&2
              exit 1
            }
            grep -qF "not a clerk envelope: Done." "$work/prose.err"

            # Prose from an agent that is not a clerk passes through unchanged.
            [ "$(ASK_AGENT_URL="$base" ${askAgent}/bin/ask-agent demo prose)" = "Done." ]

            touch "$out"
      '';
}
