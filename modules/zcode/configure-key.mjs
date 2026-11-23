import { configureCodingPlanApiKey } from "@zcode/bootstrap";
import {
  NodeModelSelectionConfigRepository,
  createNodeProviderConfigRuntime,
} from "@zcode/provider-node";
import {
  ModelConfig,
  ProviderConfigMap,
  ProviderConfigResolver,
  completeNewModelSelection,
} from "@zcode/provider";

const apiKey = process.env.ZAI_API_KEY?.trim();
if (!apiKey) throw new Error("ZAI_API_KEY is required");
async function configure() {
  const configured = await configureCodingPlanApiKey({ apiKey, providerId: "zai", env: process.env });
  const runtime = createNodeProviderConfigRuntime({
    zcodeBuiltinFilePath: process.env.ZCODE_BUILTIN_PROVIDER_CONFIG_FILE,
    personalFilePath: configured.configPath,
    personalPollingIntervalMs: false,
    watch: false,
  });
  const repository = new NodeModelSelectionConfigRepository({ personalRepository: runtime.personalRepository });
  try {
    const selection = await repository.read();
    if (!selection) throw new Error("Native key initialization produced no model selection");
    const modelId = process.env.ZCODE_DEFAULT_MODEL;
    const resolveProviders = async () => {
      const snapshot = await runtime.configService.read();
      return new ProviderConfigResolver().resolve({
        ...snapshot,
        accountProviders: new ProviderConfigMap([]),
      }).resolvedProviders;
    };
    const complete = (providers) => completeNewModelSelection({ providers }, { ...selection, modelId });
    let providers = await resolveProviders();
    let completed = complete(providers);
    // The bundled catalog trails Z.ai releases, so a brand-new default id can
    // be absent from it. Register that id as a personal model on the coding
    // plan provider (providerConfigRules.providerRules[].config.personalModelIds,
    // the same rule shape the router personal config uses) and resolve again;
    // the built-in model rules still supply the option specs.
    const known = providers
      .find((provider) => provider.providerId === selection.providerId)
      ?.models.some((model) => model.modelId === modelId);
    if (!completed && modelId && !known) {
      await runtime.configService.addPersonalModel(selection.providerId, modelId, new ModelConfig({}));
      providers = await resolveProviders();
      completed = complete(providers);
    }
    if (!completed) throw new Error("Default model is absent from the bundled provider configuration");
    await repository.saveConfiguredDefault(completed);
  } finally {
    repository.dispose();
    runtime.dispose();
  }
}

configure().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
